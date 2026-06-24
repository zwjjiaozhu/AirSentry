import AppKit
import Foundation

struct NowPlayingTrack: Identifiable {
    let id: String
    let title: String
    let artist: String?
    let album: String?
    let artwork: NSImage?
    let duration: TimeInterval?
    let elapsedTime: TimeInterval?
    let isPlaying: Bool
    let appBundleIdentifier: String?
    let appProcessIdentifier: pid_t?
}
