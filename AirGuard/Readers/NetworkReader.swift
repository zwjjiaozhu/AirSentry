import Foundation
import Darwin

final class NetworkReader {
    private var previousSample: NetworkSample?

    func readSpeed() -> NetworkSpeed {
        let current = readSample()
        defer { previousSample = current }

        guard let previousSample else { return .zero }

        let elapsed = current.date.timeIntervalSince(previousSample.date)
        guard elapsed > 0 else { return .zero }

        let uploaded = current.sentBytes >= previousSample.sentBytes ? current.sentBytes - previousSample.sentBytes : 0
        let downloaded = current.receivedBytes >= previousSample.receivedBytes ? current.receivedBytes - previousSample.receivedBytes : 0

        return NetworkSpeed(
            uploadBytesPerSecond: Double(uploaded) / elapsed,
            downloadBytesPerSecond: Double(downloaded) / elapsed
        )
    }

    private func readSample() -> NetworkSample {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        var sentBytes: UInt64 = 0
        var receivedBytes: UInt64 = 0

        guard getifaddrs(&interfaces) == 0, let firstInterface = interfaces else {
            return NetworkSample(sentBytes: 0, receivedBytes: 0, date: Date())
        }

        defer { freeifaddrs(interfaces) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = firstInterface
        while let interface = pointer?.pointee {
            defer { pointer = interface.ifa_next }

            guard let address = interface.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_LINK),
                  let data = interface.ifa_data else {
                continue
            }

            let name = String(cString: interface.ifa_name)
            guard !name.hasPrefix("lo") else { continue }

            let networkData = data.assumingMemoryBound(to: if_data.self).pointee
            sentBytes += UInt64(networkData.ifi_obytes)
            receivedBytes += UInt64(networkData.ifi_ibytes)
        }

        return NetworkSample(sentBytes: sentBytes, receivedBytes: receivedBytes, date: Date())
    }
}

private struct NetworkSample {
    var sentBytes: UInt64
    var receivedBytes: UInt64
    var date: Date
}
