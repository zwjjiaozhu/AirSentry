import AppKit
import Foundation

@MainActor
final class NowPlayingStore: ObservableObject {
    @Published private(set) var track: NowPlayingTrack?
    @Published private(set) var isAvailable = false

#if !APP_STORE
    private let bridge = ASMediaRemoteBridge()
    private let adapter = MediaRemoteAdapterClient()
    private var refreshTimer: Timer?
    private var progressTimer: Timer?
    private var lastProgressTick = Date()
#endif

    init() {
#if !APP_STORE
        let handler: ([AnyHashable: Any]?) -> Void = { [weak self] info in
            Task { @MainActor in self?.update(with: info) }
        }
        adapter.infoHandler = handler
        let adapterAvailable = adapter.start()
        bridge.infoHandler = adapterAvailable ? nil : handler
        let bridgeAvailable = bridge.start()
        isAvailable = adapterAvailable || bridgeAvailable
        NSLog(
            "[AirSentry Media] Store initialized: adapter=%@ bridge=%@ available=%@",
            adapterAvailable ? "true" : "false",
            bridgeAvailable ? "true" : "false",
            isAvailable ? "true" : "false"
        )
        if !adapterAvailable && bridgeAvailable {
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.bridge.refresh()
            }
        }
#endif
    }

    func setProgressTrackingEnabled(_ enabled: Bool) {
#if !APP_STORE
        if enabled {
            guard isAvailable, progressTimer == nil else { return }
            lastProgressTick = Date()
            progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.advancePlaybackClock() }
            }
        } else {
            progressTimer?.invalidate()
            progressTimer = nil
        }
#endif
    }

    func togglePlayPause() {
#if !APP_STORE
        bridge.togglePlayPause()
#endif
    }

    func nextTrack() {
#if !APP_STORE
        bridge.nextTrack()
#endif
    }

    func previousTrack() {
#if !APP_STORE
        bridge.previousTrack()
#endif
    }

    func openNowPlayingApp() {
        guard let track else { return }

        if let bundleIdentifier = track.appBundleIdentifier {
            if activateRunningApp(bundleIdentifier: bundleIdentifier) { return }
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                let configuration = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { app, error in
                    if let error {
                        NSLog("[AirSentry Media] Failed to open player %@: %@", bundleIdentifier, error.localizedDescription)
                    } else {
                        app?.activate(options: [.activateAllWindows])
                    }
                }
                return
            }
        }

        if let pid = track.appProcessIdentifier,
           let app = NSRunningApplication(processIdentifier: pid) {
            app.activate(options: [.activateAllWindows])
        }
    }

#if !APP_STORE
    private func update(with info: [AnyHashable: Any]?) {
        guard let info,
              let title = stringValue(in: info, keys: [
                "kMRMediaRemoteNowPlayingInfoTitle", "title", "Title"
              ]),
              !title.isEmpty else {
            NSLog("[AirSentry Media] Clearing notch music state (no valid title)")
            track = nil
            lastProgressTick = Date()
            return
        }

        let artist = stringValue(in: info, keys: ["kMRMediaRemoteNowPlayingInfoArtist", "artist", "Artist"])
        let album = stringValue(in: info, keys: ["kMRMediaRemoteNowPlayingInfoAlbum", "album", "Album"])
        let duration = numberValue(in: info, keys: ["kMRMediaRemoteNowPlayingInfoDuration", "duration"])
        let elapsedTime = numberValue(in: info, keys: ["kMRMediaRemoteNowPlayingInfoElapsedTime", "elapsedTime"])
        let playbackRate = numberValue(in: info, keys: ["kMRMediaRemoteNowPlayingInfoPlaybackRate", "playbackRate"]) ?? 0
        let artworkData = value(in: info, keys: ["kMRMediaRemoteNowPlayingInfoArtworkData", "artworkData"]) as? Data
        let artwork = artworkData.flatMap(NSImage.init(data:))
        let appBundleIdentifier = normalizedBundleIdentifier(from: info)
        let appProcessIdentifier = processIdentifier(from: info)

        track = NowPlayingTrack(
            id: [title, artist ?? "", album ?? ""].joined(separator: "|") ,
            title: title,
            artist: artist,
            album: album,
            artwork: artwork,
            duration: duration,
            elapsedTime: elapsedTime,
            isPlaying: playbackRate > 0,
            appBundleIdentifier: appBundleIdentifier,
            appProcessIdentifier: appProcessIdentifier
        )
        lastProgressTick = Date()
        NSLog("[AirSentry Media] Notch track updated: %@ — %@", title, artist ?? "")
    }

    private func advancePlaybackClock() {
        let now = Date()
        let delta = now.timeIntervalSince(lastProgressTick)
        lastProgressTick = now

        guard let current = track,
              current.isPlaying,
              let elapsedTime = current.elapsedTime else { return }

        let advanced = min(elapsedTime + max(delta, 0), current.duration ?? .greatestFiniteMagnitude)
        track = NowPlayingTrack(
            id: current.id,
            title: current.title,
            artist: current.artist,
            album: current.album,
            artwork: current.artwork,
            duration: current.duration,
            elapsedTime: advanced,
            isPlaying: current.isPlaying,
            appBundleIdentifier: current.appBundleIdentifier,
            appProcessIdentifier: current.appProcessIdentifier
        )
    }

    private func value(in info: [AnyHashable: Any], keys: [String]) -> Any? {
        for key in keys {
            if let value = info[key] { return value }
        }
        return nil
    }

    private func stringValue(in info: [AnyHashable: Any], keys: [String]) -> String? {
        value(in: info, keys: keys) as? String
    }

    private func numberValue(in info: [AnyHashable: Any], keys: [String]) -> Double? {
        (value(in: info, keys: keys) as? NSNumber)?.doubleValue
    }

    private func normalizedBundleIdentifier(from info: [AnyHashable: Any]) -> String? {
        let bundleIdentifier = stringValue(in: info, keys: [
            "parentApplicationBundleIdentifier",
            "bundleIdentifier",
            "applicationBundleIdentifier"
        ])
        guard let bundleIdentifier,
              !bundleIdentifier.isEmpty,
              bundleIdentifier != "unknown" else { return nil }
        return bundleIdentifier
    }

    private func processIdentifier(from info: [AnyHashable: Any]) -> pid_t? {
        guard let number = value(in: info, keys: ["processIdentifier"]) as? NSNumber,
              number.intValue > 0 else { return nil }
        return pid_t(number.intValue)
    }
#endif

    private func activateRunningApp(bundleIdentifier: String) -> Bool {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleIdentifier
        }) else {
            return false
        }
        app.activate(options: [.activateAllWindows])
        return true
    }
}
