import Foundation

struct NetworkSpeed: Equatable {
    var uploadBytesPerSecond: Double
    var downloadBytesPerSecond: Double

    static let zero = NetworkSpeed(uploadBytesPerSecond: 0, downloadBytesPerSecond: 0)
}
