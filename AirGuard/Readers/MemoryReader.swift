import Foundation
import Darwin.Mach
import Dispatch

struct MemoryReader {
    private let pressureMonitor = MemoryPressureMonitor()

    func read() -> MemoryInfo {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return .empty }

        let pageSize = UInt64(vm_kernel_page_size)
        let free = UInt64(stats.free_count) * pageSize
        let active = UInt64(stats.active_count) * pageSize
        let inactive = UInt64(stats.inactive_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let used = active + inactive + wired + compressed
        let total = ProcessInfo.processInfo.physicalMemory

        return MemoryInfo(
            totalBytes: total,
            usedBytes: min(used, total),
            freeBytes: free,
            pressureLevel: pressureMonitor.level
        )
    }
}

private final class MemoryPressureMonitor {
    private let lock = NSLock()
    private var currentLevel: MemoryPressureLevel = .normal
    private var source: DispatchSourceMemoryPressure?

    var level: MemoryPressureLevel {
        lock.lock()
        defer { lock.unlock() }
        return currentLevel
    }

    init() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical],
            queue: .global(qos: .utility)
        )

        source.setEventHandler { [weak self, weak source] in
            guard let source else { return }
            self?.updateLevel(from: source.data)
        }

        self.source = source
        source.resume()
    }

    deinit {
        source?.cancel()
    }

    private func updateLevel(from event: DispatchSource.MemoryPressureEvent) {
        let level: MemoryPressureLevel

        if event.contains(.critical) {
            level = .critical
        } else if event.contains(.warning) {
            level = .warning
        } else {
            level = .normal
        }

        lock.lock()
        currentLevel = level
        lock.unlock()
    }
}
