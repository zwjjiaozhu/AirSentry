import Foundation

// https://github.com/TheBoredTeam/boring.notch

final class MediaRemoteAdapterClient {
    var infoHandler: (([AnyHashable: Any]?) -> Void)?

    private let queue = DispatchQueue(label: "com.airsentry.media-adapter")
    private var process: Process?
    private var outputHandle: FileHandle?
    private var errorHandle: FileHandle?
    private var buffer = Data()
    private var payload: [String: Any] = [:]
    private var didLogSuppressedClientPropertiesWarning = false

    func start() -> Bool {
        guard process == nil,
              let frameworkURL = Bundle.main.privateFrameworksURL?
                .appendingPathComponent("MediaRemoteAdapter.framework"),
              FileManager.default.fileExists(atPath: frameworkURL.path) else {
            NSLog("[AirSentry Media] MediaRemoteAdapter.framework was not found")
            return false
        }

        let executableURL = frameworkURL.appendingPathComponent("MediaRemoteAdapter")
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            NSLog("[AirSentry Media] Adapter executable was not found: %@", executableURL.path)
            return false
        }

        let pipe = Pipe()
        let errorPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = ["-e", Self.perlLoader, executableURL.path]
        process.standardOutput = pipe
        process.standardError = errorPipe

        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.queue.async { self?.consume(data) }
        }
        let errorHandle = errorPipe.fileHandleForReading
        errorHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let message = String(data: data, encoding: .utf8) else { return }
            self?.queue.async { self?.consumeStderr(message) }
        }
        process.terminationHandler = { [weak self] _ in
            NSLog("[AirSentry Media] Adapter exited with status %d", process.terminationStatus)
            self?.queue.async {
                self?.payload.removeAll()
                self?.infoHandler?(nil)
            }
        }

        do {
            try process.run()
            self.process = process
            outputHandle = handle
            self.errorHandle = errorHandle
            NSLog("[AirSentry Media] Adapter started (pid %d): %@", process.processIdentifier, executableURL.path)
            return true
        } catch {
            handle.readabilityHandler = nil
            errorHandle.readabilityHandler = nil
            NSLog("[AirSentry Media] Failed to start adapter: %@", error.localizedDescription)
            return false
        }
    }

    func stop() {
        outputHandle?.readabilityHandler = nil
        outputHandle = nil
        errorHandle?.readabilityHandler = nil
        errorHandle = nil
        if process?.isRunning == true { process?.terminate() }
        process = nil
    }

    deinit { stop() }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[..<newline]
            buffer.removeSubrange(...newline)
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let nextPayload = object["payload"] as? [String: Any] else {
                if let text = String(data: line, encoding: .utf8) {
                    NSLog("[AirSentry Media] Unrecognized adapter output: %@", text)
                }
                continue
            }
            apply(nextPayload, isDiff: object["diff"] as? Bool ?? false)
        }
    }

    private func apply(_ update: [String: Any], isDiff: Bool) {
        if !isDiff { payload.removeAll() }
        for (key, value) in update {
            if value is NSNull { payload.removeValue(forKey: key) }
            else { payload[key] = value }
        }

        guard let title = payload["title"] as? String, !title.isEmpty else {
            NSLog("[AirSentry Media] No active track; payload=%@", payload)
            infoHandler?(nil)
            return
        }

        var info: [AnyHashable: Any] = ["kMRMediaRemoteNowPlayingInfoTitle": title]
        copy("artist", to: "kMRMediaRemoteNowPlayingInfoArtist", into: &info)
        copy("album", to: "kMRMediaRemoteNowPlayingInfoAlbum", into: &info)
        copy("duration", to: "kMRMediaRemoteNowPlayingInfoDuration", into: &info)
        copy("elapsedTime", to: "kMRMediaRemoteNowPlayingInfoElapsedTime", into: &info)
        if let artwork = payload["artworkData"] as? String,
           let data = Data(base64Encoded: artwork.trimmingCharacters(in: .whitespacesAndNewlines)) {
            info["kMRMediaRemoteNowPlayingInfoArtworkData"] = data
        }
        let isPlaying = payload["playing"] as? Bool ?? false
        let rate = (payload["playbackRate"] as? NSNumber)?.doubleValue ?? 1
        info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] = isPlaying ? rate : 0
        copy("parentApplicationBundleIdentifier", to: "parentApplicationBundleIdentifier", into: &info)
        copy("bundleIdentifier", to: "bundleIdentifier", into: &info)
        copy("processIdentifier", to: "processIdentifier", into: &info)
        let artist = payload["artist"] as? String ?? ""
        let elapsed = payload["elapsedTime"] ?? 0
        let duration = payload["duration"] ?? 0
        let bundle = payload["parentApplicationBundleIdentifier"]
            ?? payload["bundleIdentifier"]
            ?? "unknown"
        NSLog("[AirSentry Media] Now playing: \(title) — \(artist) | playing=\(isPlaying) | elapsed=\(elapsed) | duration=\(duration) | bundle=\(bundle)")
        infoHandler?(info)
    }

    private func consumeStderr(_ message: String) {
        for line in message.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if isBenignClientPropertiesPermissionWarning(trimmed) {
                if !didLogSuppressedClientPropertiesWarning {
                    didLogSuppressedClientPropertiesWarning = true
                    NSLog("[AirSentry Media] Suppressing benign MediaRemote clientProperties permission warnings")
                }
                continue
            }

            NSLog("[AirSentry Media] Adapter stderr: %@", trimmed)
        }
    }

    private func isBenignClientPropertiesPermissionWarning(_ line: String) -> Bool {
        line.contains("clientProperties")
            && line.contains("kMRMediaRemoteFrameworkErrorDomain Code=3")
            && line.contains("Operation not permitted")
    }

    private func copy(_ source: String, to destination: String, into info: inout [AnyHashable: Any]) {
        if let value = payload[source] { info[destination] = value }
    }

    private static let perlLoader = #"""
    use strict;
    use warnings;
    use DynaLoader;
    my $framework = shift @ARGV;
    my $handle = DynaLoader::dl_load_file($framework, 0) or die "Unable to load media adapter";
    my $symbol = DynaLoader::dl_find_symbol($handle, "adapter_stream") or die "Missing adapter_stream";
    DynaLoader::dl_install_xsub("main::stream", $symbol);
    main::stream();
    """#
}
