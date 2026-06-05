import Foundation

enum DateFormatterUtil {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    static func timeString(from date: Date) -> String {
        timeFormatter.string(from: date)
    }
}
