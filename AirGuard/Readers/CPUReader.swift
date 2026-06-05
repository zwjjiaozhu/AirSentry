import Foundation
import Darwin.Mach

final class CPUReader {
    private var previousInfo: host_cpu_load_info?

    func readUsage() -> Double {
        guard let info = currentCPUInfo() else { return 0 }
        defer { previousInfo = info }

        guard let previousInfo else { return 0 }

        let user = Double(info.cpu_ticks.0 - previousInfo.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1 - previousInfo.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2 - previousInfo.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3 - previousInfo.cpu_ticks.3)
        let total = user + system + idle + nice

        guard total > 0 else { return 0 }
        return min(max((user + system + nice) / total, 0), 1)
    }

    private func currentCPUInfo() -> host_cpu_load_info? {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        var cpuInfo = host_cpu_load_info()

        let result = withUnsafeMutablePointer(to: &cpuInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }

        return result == KERN_SUCCESS ? cpuInfo : nil
    }
}

struct ProcessCPUReader {
    func readTopProcesses(limit: Int = 3) -> [TopCPUProcess] {
        let process = Process()
        let outputPipe = Pipe()
        let outputQueue = DispatchQueue(label: "airsentry.process-cpu-reader.output")
        let outputGroup = DispatchGroup()
        let timeout: TimeInterval = 2
        var outputData = Data()

        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,pcpu=,comm="]
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return []
        }

        outputGroup.enter()
        outputQueue.async {
            outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            outputGroup.leave()
        }

        guard wait(for: process, timeout: timeout) else {
            process.terminate()
            _ = wait(for: process, timeout: 0.5)
            outputPipe.fileHandleForReading.closeFile()
            outputGroup.wait()
            return []
        }

        outputGroup.wait()
        guard process.terminationStatus == 0 else { return [] }

        guard let output = String(data: outputData, encoding: .utf8) else { return [] }

        return output
            .split(separator: "\n")
            .compactMap(parseProcessLine)
            .filter { $0.cpuPercent > 0 }
            .sorted { $0.cpuPercent > $1.cpuPercent }
            .prefix(limit)
            .map { $0 }
    }

    private func wait(for process: Process, timeout: TimeInterval) -> Bool {
        let group = DispatchGroup()
        group.enter()

        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            group.leave()
        }

        return group.wait(timeout: .now() + timeout) == .success
    }

    private func parseProcessLine(_ line: Substring) -> TopCPUProcess? {
        let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count == 3,
              let pid = Int32(parts[0]),
              let cpuPercent = Double(parts[1])
        else {
            return nil
        }

        let rawCommand = String(parts[2])
        let name = URL(fileURLWithPath: rawCommand).lastPathComponent
        guard !name.isEmpty else { return nil }

        return TopCPUProcess(pid: pid, cpuPercent: cpuPercent, name: name)
    }
}
