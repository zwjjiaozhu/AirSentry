import Combine
import Foundation

@MainActor
final class MonitorStore: ObservableObject {
    @Published private(set) var snapshot: SystemSnapshot = .empty
    @Published private(set) var cpuUsageHistory: [Double] = []
    @Published private(set) var networkDownloadHistory: [Double] = []
    @Published private(set) var networkUploadHistory: [Double] = []
    @Published private(set) var topCPUProcesses: [TopCPUProcess] = []
    @Published private(set) var isRefreshingTopCPUProcesses = false

    private let settings: AppSettings
    private let alertManager: AlertManager
    private let thermalLogArchiver = LogArchiver.shared
    private let thermalReader = ThermalReader()
    private let cpuReader = CPUReader()
    private let processCPUReader = ProcessCPUReader()
    private let memoryReader = MemoryReader()
    private let networkReader = NetworkReader()
    private let maxHistorySamples = 24
    private let topProcessRefreshInterval: TimeInterval = 10
    private let thermalLogInterval: TimeInterval = 120
    private var lastTopProcessRefreshDate: Date?
    private var lastThermalLogDate: Date?
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(settings: AppSettings, alertManager: AlertManager) {
        self.settings = settings
        self.alertManager = alertManager
        bindSettings()
        refresh()
        startTimer()
    }

    func refresh() {
        let thermalStatus = settings.effectiveThermalStatus(from: thermalReader.read())
        let snapshot = SystemSnapshot(
            thermal: thermalStatus,
            cpuUsage: cpuReader.readUsage(),
            memory: memoryReader.read(),
            network: networkReader.readSpeed(),
            battery: .empty,
            disk: .empty,
            capturedAt: Date()
        )
        self.snapshot = snapshot
        appendHistory(from: snapshot)
        refreshTopCPUProcessesIfNeeded(for: snapshot)
        logThermalEventIfNeeded(for: snapshot)
        alertManager.handle(snapshot: snapshot, settings: settings)
    }

    var cpuSparklineValues: [Double] {
        paddedHistory(cpuUsageHistory, fallback: snapshot.cpuUsage)
    }

    var networkDownloadSparklineValues: [Double] {
        let values = paddedHistory(networkDownloadHistory, fallback: snapshot.network.downloadBytesPerSecond)
        return normalizedNetworkValues(values)
    }

    var networkUploadSparklineValues: [Double] {
        let values = paddedHistory(networkUploadHistory, fallback: snapshot.network.uploadBytesPerSecond)
        return normalizedNetworkValues(values)
    }

    private func bindSettings() {
        settings.$refreshInterval
            .removeDuplicates()
            .sink { [weak self] _ in self?.startTimer() }
            .store(in: &cancellables)

        Publishers.CombineLatest3(
            settings.$fairTemperatureThreshold,
            settings.$seriousTemperatureThreshold,
            settings.$criticalTemperatureThreshold
        )
        .dropFirst()
        .sink { [weak self] _ in
            self?.refresh()
        }
        .store(in: &cancellables)
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: max(settings.refreshInterval, 1), repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    private func appendHistory(from snapshot: SystemSnapshot) {
        append(snapshot.cpuUsage, to: &cpuUsageHistory)
        append(snapshot.network.downloadBytesPerSecond, to: &networkDownloadHistory)
        append(snapshot.network.uploadBytesPerSecond, to: &networkUploadHistory)
    }

    private func refreshTopCPUProcessesIfNeeded(for snapshot: SystemSnapshot) {
        guard snapshot.thermal.level.severity >= settings.alertThermalLevel.severity else {
            topCPUProcesses = []
            lastTopProcessRefreshDate = nil
            isRefreshingTopCPUProcesses = false
            return
        }

        guard !isRefreshingTopCPUProcesses else { return }

        let now = Date()
        if let lastTopProcessRefreshDate,
           now.timeIntervalSince(lastTopProcessRefreshDate) < topProcessRefreshInterval {
            return
        }

        isRefreshingTopCPUProcesses = true
        lastTopProcessRefreshDate = now

        Task.detached(priority: .utility) { [weak self, processCPUReader] in
            let processes = processCPUReader.readTopProcesses()
            await self?.finishTopCPUProcessRefresh(with: processes)
        }
    }

    private func logThermalEventIfNeeded(for snapshot: SystemSnapshot) {
        guard snapshot.thermal.level.severity >= settings.alertThermalLevel.severity else {
            return
        }

        let now = Date()
        if let lastThermalLogDate,
           now.timeIntervalSince(lastThermalLogDate) < thermalLogInterval {
            return
        }
        lastThermalLogDate = now

        let message = buildThermalLogMessage(snapshot, topProcesses: topCPUProcesses)
        thermalLogArchiver.warning(message)
    }

    private func finishTopCPUProcessRefresh(with processes: [TopCPUProcess]) {
        isRefreshingTopCPUProcesses = false

        guard snapshot.thermal.level.severity >= settings.alertThermalLevel.severity else {
            topCPUProcesses = []
            lastTopProcessRefreshDate = nil
            return
        }

        topCPUProcesses = processes

        // 进程列表刷新后，补记一条带进程信息的日志
        let message = buildThermalLogMessage(snapshot, topProcesses: processes)
        thermalLogArchiver.warning(message)
        lastThermalLogDate = Date()
    }

    // MARK: - 日志内容构建（监控线程自己决定打什么）

    private func buildThermalLogMessage(_ snapshot: SystemSnapshot, topProcesses: [TopCPUProcess]) -> String {
        let tempStr = snapshot.thermal.temperatureCelsius.map { String(format: "%.1f°C", $0) } ?? "N/A"
        let cpuPercent = String(format: "%.0f%%", snapshot.cpuUsage * 100)

        var lines: [String] = []
        lines.append("thermal_level=\(snapshot.thermal.level.title)(\(snapshot.thermal.level.severity)) temp=\(tempStr) cpu=\(cpuPercent)")
        lines.append("  memory:       \(formatMemory(snapshot.memory))")
        lines.append("  network:      ↓\(formatBytes(snapshot.network.downloadBytesPerSecond))/s  ↑\(formatBytes(snapshot.network.uploadBytesPerSecond))/s")
        lines.append("  thresholds:   fair=\(Int(settings.fairTemperatureThreshold))°C  serious=\(Int(settings.seriousTemperatureThreshold))°C  critical=\(Int(settings.criticalTemperatureThreshold))°C")

        if !topProcesses.isEmpty {
            lines.append("  ── top CPU processes ──")
            for proc in topProcesses {
                lines.append("    PID \(proc.pid)\t\(String(format: "%6.1f%%", proc.cpuPercent))\t\(proc.name)")
            }
        } else {
            lines.append("  top processes: N/A")
        }

        return lines.joined(separator: "\n")
    }

    private func formatMemory(_ memory: MemoryInfo) -> String {
        guard memory.totalBytes > 0 else { return "N/A" }
        let usedGB = Double(memory.usedBytes) / 1_073_741_824
        let totalGB = Double(memory.totalBytes) / 1_073_741_824
        return String(format: "%.1f/%.1f GB (%.0f%%, %@)", usedGB, totalGB, memory.usageRatio * 100, memory.pressureLevel.title)
    }

    private func formatBytes(_ bytes: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func append(_ value: Double, to history: inout [Double]) {
        history.append(value)
        if history.count > maxHistorySamples {
            history.removeFirst(history.count - maxHistorySamples)
        }
    }

    private func paddedHistory(_ history: [Double], fallback: Double) -> [Double] {
        guard !history.isEmpty else { return [fallback, fallback] }
        guard history.count == 1 else { return history }
        return [history[0], history[0]]
    }

    private func normalizedNetworkValues(_ values: [Double]) -> [Double] {
        let downloadValues = paddedHistory(networkDownloadHistory, fallback: snapshot.network.downloadBytesPerSecond)
        let uploadValues = paddedHistory(networkUploadHistory, fallback: snapshot.network.uploadBytesPerSecond)
        let maxValue = max(max(downloadValues.max() ?? 0, uploadValues.max() ?? 0), 1)
        return values.map { min(max($0 / maxValue, 0), 1) }
    }
}
