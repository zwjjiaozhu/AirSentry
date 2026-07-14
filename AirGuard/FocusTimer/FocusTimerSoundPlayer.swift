import AppKit

enum FocusTimerCompletionSound: String, CaseIterable, Identifiable {
    case glass = "Glass"
    case ping = "Ping"
    case hero = "Hero"
    case basso = "Basso"
    case blow = "Blow"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .glass: "清脆"
        case .ping: "轻响"
        case .hero: "明亮"
        case .basso: "低音"
        case .blow: "柔和"
        }
    }
}

@MainActor
final class FocusTimerSoundPlayer: NSObject, NSSoundDelegate {
    static let shared = FocusTimerSoundPlayer()

    private var activeSounds: [NSSound] = []

    func playCompletionSound(named soundName: String, repeatCount: Int = 2) {
        let count = max(repeatCount, 1)
        for index in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.65) { [weak self] in
                self?.playSound(named: soundName)
            }
        }
    }

    private func playSound(named soundName: String) {
        guard let sound = NSSound(named: soundName) ?? NSSound(named: FocusTimerCompletionSound.ping.rawValue) else {
            NSSound.beep()
            return
        }

        sound.delegate = self
        activeSounds.append(sound)
        sound.play()
    }

    func sound(_ sound: NSSound, didFinishPlaying finishedPlaying: Bool) {
        activeSounds.removeAll { $0 === sound }
    }
}
