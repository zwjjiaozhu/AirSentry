import AppKit
import Foundation
import UserNotifications

enum FocusTimerMode: Equatable {
    case focus
    case breakTime
    case quickTimer

    var title: String {
        switch self {
        case .focus: "专注中"
        case .breakTime: "休息中"
        case .quickTimer: "计时中"
        }
    }

    var icon: String {
        switch self {
        case .focus: "timer"
        case .breakTime: "leaf"
        case .quickTimer: "stopwatch"
        }
    }
}

struct FocusTimerPreset: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let focusMinutes: Int
    let breakMinutes: Int?
    let mode: FocusTimerMode

    static let rhythmPresets: [FocusTimerPreset] = [
        .init(id: "pomodoro-25-5", title: "标准专注节奏", subtitle: "25 / 5 节律", focusMinutes: 25, breakMinutes: 5, mode: .focus),
        .init(id: "eye-40-3", title: "让眼睛放松一下", subtitle: "40 / 3 节律", focusMinutes: 40, breakMinutes: 3, mode: .focus),
        .init(id: "walk-60-5", title: "休息一下，走一走", subtitle: "60 / 5 节律", focusMinutes: 60, breakMinutes: 5, mode: .focus)
    ]

    static let quickPresets: [FocusTimerPreset] = [
        .init(id: "quick-5", title: "先把这步做完", subtitle: "5M", focusMinutes: 5, breakMinutes: nil, mode: .quickTimer),
        .init(id: "quick-10", title: "把思路理顺", subtitle: "10M", focusMinutes: 10, breakMinutes: nil, mode: .quickTimer),
        .init(id: "quick-25", title: "心无旁骛", subtitle: "25M", focusMinutes: 25, breakMinutes: nil, mode: .quickTimer),
        .init(id: "quick-30", title: "这一段很关键", subtitle: "30M", focusMinutes: 30, breakMinutes: nil, mode: .quickTimer),
        .init(id: "quick-45", title: "晚上适合收尾", subtitle: "45M", focusMinutes: 45, breakMinutes: nil, mode: .quickTimer),
        .init(id: "quick-60", title: "大块时间大块产出", subtitle: "60M", focusMinutes: 60, breakMinutes: nil, mode: .quickTimer),
        .init(id: "quick-90", title: "把这轮拉到底", subtitle: "90M", focusMinutes: 90, breakMinutes: nil, mode: .quickTimer)
    ]
}

@MainActor
final class FocusTimerStore: ObservableObject {
    @Published private(set) var mode: FocusTimerMode?
    @Published private(set) var isRunning = false
    @Published private(set) var isPaused = false
    @Published private(set) var title = "时间节律"
    @Published private(set) var remainingSeconds = 0
    @Published private(set) var totalSeconds = 0
    @Published private(set) var pendingBreakMinutes: Int?
    @Published var showsFloatingReminder = false

    private let settings: AppSettings
    private var ticker: Timer?
    private var endDate: Date?
    private var pausedRemainingSeconds: Int?

    init(settings: AppSettings) {
        self.settings = settings
    }

    var isActive: Bool {
        mode != nil && remainingSeconds > 0
    }

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return 1 - (Double(remainingSeconds) / Double(totalSeconds))
    }

    var displayTime: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func start(_ preset: FocusTimerPreset) {
        start(
            mode: preset.mode,
            title: preset.title,
            minutes: preset.focusMinutes,
            breakMinutes: preset.breakMinutes
        )
    }

    func startBreak() {
        guard let pendingBreakMinutes else { return }
        start(mode: .breakTime, title: "休息一下", minutes: pendingBreakMinutes, breakMinutes: nil)
    }

    func togglePause() {
        guard isActive else { return }
        isPaused ? resume() : pause()
    }

    func extend(minutes: Int = 5) {
        guard isActive else { return }
        remainingSeconds += minutes * 60
        totalSeconds += minutes * 60
        if isRunning {
            endDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        }
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        mode = nil
        isRunning = false
        isPaused = false
        title = "时间节律"
        remainingSeconds = 0
        totalSeconds = 0
        pendingBreakMinutes = nil
        endDate = nil
        pausedRemainingSeconds = nil
        showsFloatingReminder = false
    }

    private func start(mode: FocusTimerMode, title: String, minutes: Int, breakMinutes: Int?) {
        ticker?.invalidate()
        self.mode = mode
        self.title = title
        self.remainingSeconds = max(minutes, 1) * 60
        self.totalSeconds = self.remainingSeconds
        self.pendingBreakMinutes = breakMinutes
        self.isRunning = true
        self.isPaused = false
        self.showsFloatingReminder = false
        self.endDate = Date().addingTimeInterval(TimeInterval(self.remainingSeconds))
        startTicker()
        NotificationCenter.default.post(name: .focusTimerDidStart, object: nil)
    }

    private func pause() {
        pausedRemainingSeconds = remainingSeconds
        isRunning = false
        isPaused = true
        ticker?.invalidate()
        ticker = nil
    }

    private func resume() {
        let seconds = pausedRemainingSeconds ?? remainingSeconds
        remainingSeconds = seconds
        endDate = Date().addingTimeInterval(TimeInterval(seconds))
        isRunning = true
        isPaused = false
        pausedRemainingSeconds = nil
        startTicker()
    }

    private func startTicker() {
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func tick() {
        guard let endDate else { return }
        remainingSeconds = max(Int(ceil(endDate.timeIntervalSinceNow)), 0)
        if remainingSeconds <= 0 {
            completeCurrentRound()
        }
    }

    private func completeCurrentRound() {
        ticker?.invalidate()
        ticker = nil
        isRunning = false
        isPaused = false
        remainingSeconds = 0
        showsFloatingReminder = true

        let completedMode = mode
        if completedMode == .focus, pendingBreakMinutes != nil {
            sendNotification(title: "专注完成", body: "这一轮完成了，可以休息一下。")
        } else if completedMode == .breakTime {
            sendNotification(title: "休息结束", body: "回来继续下一轮吧。")
        } else {
            sendNotification(title: "计时完成", body: "\(title) 已到时间。")
        }
    }

    private func sendNotification(title: String, body: String) {
        guard settings.notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "airsentry.focusTimer.\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

extension Notification.Name {
    static let focusTimerDidStart = Notification.Name("AirSentry.FocusTimerDidStart")
    static let showFocusTimerLauncher = Notification.Name("AirSentry.ShowFocusTimerLauncher")
}
