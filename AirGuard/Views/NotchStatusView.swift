import AppKit
import SwiftUI

struct NotchStatusView: View {
    @ObservedObject var store: AgentMonitorStore
    @ObservedObject var nowPlayingStore: NowPlayingStore
    @ObservedObject var presentation: NotchPresentationState
    let onOpenSession: (AgentSession) -> Void
    let onCollapse: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if !presentation.showsMusic, let session = store.primarySession {
                if presentation.notchHeight > 0 {
                    VStack(spacing: 0) {
                        notchWingRow(session)

                        if presentation.isExpanded {
                            expandedContent(primary: session)
                                .clipped()
                                .transition(expandedContentTransition)
                        }
                    }
                    .background(.black)
                    .clipShape(NotchShoulderShape())
                } else {
                    Group {
                        if presentation.isExpanded {
                            expandedContent(primary: session)
                        } else {
                            compactContent(session)
                        }
                    }
                    .background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            } else if presentation.showsMusic, let track = nowPlayingStore.track {
                if presentation.notchHeight > 0 {
                    VStack(spacing: 0) {
                        musicWingRow(track)

                        if presentation.isExpanded {
                            Color.black
                                .frame(height: presentation.expandedContentTopInset)
                                .transition(.opacity)

                            musicExpandedContent(track)
                                .clipped()
                                .transition(expandedContentTransition)
                        }
                    }
                    .background(.black)
                    .clipShape(NotchShoulderShape())
                } else {
                    musicExpandedContent(track)
                        .background(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.26), value: presentation.isExpanded)
    }

    private var expandedContentTransition: AnyTransition {
        .opacity
    }

    private func musicWingRow(_ track: NowPlayingTrack) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                if !presentation.isExpanded {
                    artworkView(track, size: 24)
                }
            }
            .padding(.leading, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(.black)

            Color.black.frame(width: presentation.notchWidth)

            HStack(spacing: 6) {
                if !presentation.isExpanded {
                    MusicActivityIndicator(isPlaying: track.isPlaying)
                        .frame(width: 29, height: 23)
                }
            }
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .background(.black)
        }
        .frame(height: presentation.notchHeight)
    }

    private func musicExpandedContent(_ track: NowPlayingTrack) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                nowPlayingStore.openNowPlayingApp()
            } label: {
                artworkView(track, size: 56)
            }
            .buttonStyle(MusicArtworkButtonStyle())
            .modifier(MusicArtworkHoverEffect())
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .help("打开播放器")

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(track.title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)

                        if !track.isPlaying {
                            Image(systemName: "pause.circle.fill")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.42))
                        }
                    }

                    Text(subtitle(for: track))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                HStack(spacing: 20) {
                    Spacer(minLength: 0)

                    Button {
                        nowPlayingStore.previousTrack()
                    } label: {
                        Image(systemName: "backward.fill")
                    }
                    .buttonStyle(MusicControlButtonStyle(size: 26))
                    .modifier(MusicControlHoverEffect())

                    Button {
                        nowPlayingStore.togglePlayPause()
                    } label: {
                        Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(MusicControlButtonStyle(size: 32, isProminent: true))
                    .modifier(MusicControlHoverEffect(isProminent: true))

                    Button {
                        nowPlayingStore.nextTrack()
                    } label: {
                        Image(systemName: "forward.fill")
                    }
                    .buttonStyle(MusicControlButtonStyle(size: 26))
                    .modifier(MusicControlHoverEffect())

                    Spacer(minLength: 0)
                }

                musicProgress(track)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .padding(.top, 11)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .center)
        .background(
            LinearGradient(
                colors: [.white.opacity(0.14), .white.opacity(0.08), .white.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    @ViewBuilder
    private func musicProgress(_ track: NowPlayingTrack) -> some View {
        if let duration = track.duration, duration > 0 {
            let elapsed = min(max(track.elapsedTime ?? 0, 0), duration)
            let progress = min(max(elapsed / duration, 0), 1)

            VStack(spacing: 4) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.30))
                        Capsule()
                            .fill(Color(red: 0.08, green: 0.48, blue: 0.98))
                            .frame(width: max(4, proxy.size.width * progress))
                    }
                }
                .frame(height: 3)

                HStack {
                    Text(playbackTime(elapsed))
                    Spacer()
                    Text("-\(playbackTime(duration - elapsed))")
                }
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
            }
        } else {
            Capsule()
                .fill(.white.opacity(0.26))
                .frame(width: 26, height: 3)
        }
    }

    private func subtitle(for track: NowPlayingTrack) -> String {
        if let artist = track.artist, let album = track.album, !album.isEmpty, album != artist {
            return "\(artist) – \(album)"
        }
        return track.artist ?? track.album ?? "正在播放"
    }

    private func playbackTime(_ interval: TimeInterval) -> String {
        guard interval.isFinite, interval >= 0 else { return "0:00" }
        let seconds = Int(interval.rounded(.down))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    @ViewBuilder
    private func artworkView(_ track: NowPlayingTrack, size: CGFloat) -> some View {
        if let artwork = track.artwork {
            Image(nsImage: artwork)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
        } else {
            Image(systemName: "music.note")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white.opacity(0.84))
                .frame(width: size, height: size)
                .background(.purple.opacity(0.7), in: RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
        }
    }

    private func notchWingRow(_ session: AgentSession) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                miniProviderBadge(session.provider)
                if presentation.isExpanded || session.state == .waitingForApproval {
                    Text(session.provider.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                }
            }
            .padding(.leading, 9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(.black)

            // Keep the whole physical-notch row black while reserving the
            // camera housing width so content remains on the two visible ends.
            Color.black
                .frame(width: presentation.notchWidth)

            HStack(spacing: 7) {
                if presentation.isExpanded || session.state == .waitingForApproval {
                    Text(wingStatusText(session.state))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(stateColor(session.state))
                        .lineLimit(1)
                }
                stateIndicator(session.state)
            }
            .padding(.trailing, 9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .background(.black)
        }
        .frame(height: presentation.notchHeight)
    }

    private func compactContent(_ session: AgentSession) -> some View {
        HStack(spacing: 10) {
            providerBadge(session.provider)

            Text(statusTitle(session))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            if session.state == .waitingForApproval,
               let project = session.project {
                Text(project)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }

            Spacer(minLength: 2)
            stateIndicator(session.state)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 42, maxHeight: 42)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(stateColor(session.state).opacity(0.82))
                .frame(height: 2)
                .padding(.horizontal, 14)
        }
    }

    private func expandedContent(primary: AgentSession) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("活动会话")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                Spacer()
                Text("\(store.sessions.count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.10), in: Capsule())

                Button("收起", action: onCollapse)
                    .buttonStyle(NotchButtonStyle())
            }
            .padding(.horizontal, 16)
            .frame(height: 42)

            if !store.sessions.isEmpty {
                Divider().overlay(.white.opacity(0.12))

                VStack(spacing: 0) {
                    ForEach(Array(orderedSessions.prefix(3))) { session in
                        sessionRow(session)
                        if session.id != orderedSessions.prefix(3).last?.id {
                            Divider()
                                .overlay(.white.opacity(0.08))
                                .padding(.leading, 42)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func sessionRow(_ session: AgentSession) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(stateColor(session.state))
                .frame(width: 7, height: 7)

            Text(session.provider.title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .frame(width: 48, alignment: .leading)

            Text(session.project ?? "未知项目")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(1)

            Spacer()

            Text(shortAction(session.action))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)

            Button(session.state == .waitingForApproval ? "去处理" : "打开") {
                onOpenSession(session)
            }
            .buttonStyle(NotchButtonStyle(isProminent: session.state == .waitingForApproval))
            .disabled(session.workingDirectory == nil && session.provider != .codex)
        }
        .padding(.horizontal, 16)
        .frame(height: 30)
    }

    private var orderedSessions: [AgentSession] {
        store.sessions.sorted {
            if $0.state.priority != $1.state.priority {
                return $0.state.priority > $1.state.priority
            }
            return $0.updatedAt > $1.updatedAt
        }
    }

    private func providerBadge(_ provider: AgentProvider) -> some View {
        Text(provider == .codex ? "CX" : "CL")
            .font(.system(size: 10, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 27, height: 27)
            .background(provider == .codex ? Color.blue : Color.orange, in: Circle())
    }

    private func miniProviderBadge(_ provider: AgentProvider) -> some View {
        Text(provider == .codex ? "CX" : "CL")
            .font(.system(size: 8.5, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(provider == .codex ? Color.blue : Color.orange, in: Circle())
    }

    @ViewBuilder
    private func stateIndicator(_ state: AgentActivityState) -> some View {
        if state == .working {
            ProgressView()
                .controlSize(.small)
                .tint(.white.opacity(0.85))
        } else {
            Image(systemName: stateSymbol(state))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(stateColor(state))
        }
    }

    private func statusTitle(_ session: AgentSession) -> String {
        switch session.state {
        case .working: "\(session.provider.title) 正在工作"
        case .waitingForApproval: "\(session.provider.title) 需要你的操作"
        case .completed: "\(session.provider.title) 任务已完成"
        case .failed: "\(session.provider.title) 任务失败"
        }
    }

    private func shortAction(_ action: String?) -> String {
        switch action {
        case "SessionStart": "会话已开始"
        case "UserPromptSubmit": "正在思考"
        case "PreToolUse": "正在调用工具"
        case "PostToolUse": "工具执行完成"
        case "PermissionRequest": "等待批准"
        case "Stop": "已结束"
        case .some(let action): action
        case .none: ""
        }
    }

    private func stateColor(_ state: AgentActivityState) -> Color {
        switch state {
        case .working: .blue
        case .waitingForApproval: .orange
        case .completed: .green
        case .failed: .red
        }
    }

    private func stateSymbol(_ state: AgentActivityState) -> String {
        switch state {
        case .working: "ellipsis"
        case .waitingForApproval: "hand.raised.fill"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private func wingStatusText(_ state: AgentActivityState) -> String {
        switch state {
        case .working: "工作中"
        case .waitingForApproval: "需操作"
        case .completed: "已完成"
        case .failed: "失败"
        }
    }
}

private struct MusicActivityIndicator: View {
    let isPlaying: Bool

    var body: some View {
        MusicBarsRepresentable(isPlaying: isPlaying)
        .accessibilityLabel(isPlaying ? "音乐正在播放" : "音乐已暂停")
    }
}

private struct MusicBarsRepresentable: NSViewRepresentable {
    let isPlaying: Bool

    func makeNSView(context: Context) -> MusicBarsView {
        let view = MusicBarsView()
        view.isPlaying = isPlaying
        return view
    }

    func updateNSView(_ nsView: MusicBarsView, context: Context) {
        nsView.isPlaying = isPlaying
    }
}

private final class MusicBarsView: NSView {
    var isPlaying = false {
        didSet {
            guard oldValue != isPlaying else { return }
            updateAnimations()
        }
    }

    private let bars: [CALayer] = (0..<4).map { _ in
        let layer = CALayer()
        layer.backgroundColor = NSColor.white.cgColor
        layer.cornerRadius = 1.5
        return layer
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        bars.forEach { layer?.addSublayer($0) }
        updateAnimations()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let barWidth: CGFloat = 3
        let spacing: CGFloat = 2.5
        let totalWidth = CGFloat(bars.count) * barWidth + CGFloat(bars.count - 1) * spacing
        let startX = (bounds.width - totalWidth) / 2
        for (index, bar) in bars.enumerated() {
            let height: CGFloat = isPlaying ? 12 : (index.isMultiple(of: 2) ? 7 : 11)
            bar.bounds = CGRect(x: 0, y: 0, width: barWidth, height: height)
            bar.position = CGPoint(
                x: startX + CGFloat(index) * (barWidth + spacing) + barWidth / 2,
                y: bounds.midY
            )
        }
        CATransaction.commit()
    }

    private func updateAnimations() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        for (index, bar) in bars.enumerated() {
            bar.removeAnimation(forKey: "musicPulse")
            bar.opacity = isPlaying ? 0.82 : 0.46
            bar.transform = CATransform3DIdentity

            guard isPlaying else { continue }

            let animation = CABasicAnimation(keyPath: "transform.scale.y")
            animation.fromValue = 0.45 + Double(index % 2) * 0.14
            animation.toValue = 1.35 + Double(index % 3) * 0.08
            animation.duration = 0.42 + Double(index) * 0.055
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animation.beginTime = CACurrentMediaTime() + Double(index) * 0.075
            bar.add(animation, forKey: "musicPulse")
        }

        CATransaction.commit()
        needsLayout = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            bars.forEach { $0.removeAllAnimations() }
        } else {
            updateAnimations()
        }
    }
}

private struct NotchShoulderShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(16, rect.height * 0.62, rect.width * 0.10)
        var path = Path()

        // The black area is widest at the screen edge and gently contracts
        // toward the physical notch row as it moves downward.
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.width - radius, y: rect.height),
            control: CGPoint(x: rect.width, y: rect.height)
        )
        path.addLine(to: CGPoint(x: radius, y: rect.height))
        path.addQuadCurve(
            to: CGPoint(x: 0, y: rect.height - radius),
            control: CGPoint(x: 0, y: rect.height)
        )
        path.addLine(to: CGPoint(x: 0, y: 0))
        path.closeSubpath()
        return path
    }
}

private struct NotchButtonStyle: ButtonStyle {
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(isProminent ? Color.black : Color.white.opacity(0.86))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                isProminent ? Color.orange.opacity(configuration.isPressed ? 0.72 : 0.95) : Color.white.opacity(configuration.isPressed ? 0.08 : 0.14),
                in: Capsule()
            )
    }
}

private struct MusicArtworkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.04 : 0)
    }
}

private struct MusicControlButtonStyle: ButtonStyle {
    let size: CGFloat
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: isProminent ? size * 0.64 : size * 0.50, weight: .bold))
            .foregroundStyle(Color.white.opacity(configuration.isPressed ? 0.72 : 0.92))
            .frame(width: size, height: size)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct MusicArtworkHoverEffect: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .brightness(isHovering ? 0.05 : 0)
            .saturation(isHovering ? 1.08 : 1)
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(.white.opacity(isHovering ? 0.42 : 0), lineWidth: 1)
            }
            .scaleEffect(isHovering ? 1.055 : 1)
            .shadow(
                color: .black.opacity(isHovering ? 0.30 : 0.22),
                radius: isHovering ? 10 : 7,
                y: isHovering ? 5 : 3
            )
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHovering)
            .onHover { hovering in
                guard hovering != isHovering else { return }
                isHovering = hovering
                if hovering {
                    NotchHaptics.performHover()
                }
            }
    }
}

private struct MusicControlHoverEffect: ViewModifier {
    var isProminent = false
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background(
                Circle()
                    .fill(Color.white.opacity(isHovering ? (isProminent ? 0.18 : 0.12) : 0))
            )
            .scaleEffect(isHovering ? (isProminent ? 1.10 : 1.08) : 1)
            .shadow(
                color: Color.white.opacity(isHovering && isProminent ? 0.22 : 0),
                radius: isHovering && isProminent ? 8 : 0
            )
            .animation(.spring(response: 0.20, dampingFraction: 0.70), value: isHovering)
            .onHover { hovering in
                guard hovering != isHovering else { return }
                isHovering = hovering
                if hovering {
                    NotchHaptics.performHover()
                }
            }
    }
}

private enum NotchHaptics {
    static func performHover() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}

@MainActor
final class NotchPresentationState: ObservableObject {
    @Published var notchHeight: CGFloat = 0
    @Published var notchWidth: CGFloat = 0
    @Published var expandedContentTopInset: CGFloat = 0
    @Published var isExpanded = false
    @Published var showsMusic = false
}
