import AppKit
import Combine
import SwiftUI

@MainActor
final class NotchWindowController {
    private let store: AgentMonitorStore
    private let settings: AppSettings
    private let panel: AgentNotchPanel
    private let presentation = NotchPresentationState()
    private var isHoverExpanded = false
    private var isAutoExpanded = false
    private var hoverFrame: NSRect = .zero
    private var lastMusicTrackID: String?
    private var autoCollapseTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var screenObserver: NSObjectProtocol?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?

    init(store: AgentMonitorStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        panel = AgentNotchPanel()
        panel.contentView = NSHostingView(rootView: NotchStatusView(
            store: store,
            nowPlayingStore: store.nowPlayingStore,
            presentation: presentation,
            onOpenSession: { [weak store] session in
                store?.openSession(session)
            },
            onCollapse: { [weak self] in self?.collapse() }
        ))

        Publishers.CombineLatest(store.$sessions, settings.$agentNotchEnabled)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.refresh() }
            .store(in: &cancellables)

        let musicTrackChanges = store.nowPlayingStore.$track
            .removeDuplicates { previous, current in
                previous?.id == current?.id
            }

        Publishers.CombineLatest(musicTrackChanges, settings.$musicNotchEnabled)
            .receive(on: RunLoop.main)
            .sink { [weak self] track, enabled in
                self?.musicTrackDidChange(track, enabled: enabled)
            }
            .store(in: &cancellables)

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh(animated: false) }
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            let location = NSEvent.mouseLocation
            Task { @MainActor in self?.updateHover(at: location) }
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            let location = NSEvent.mouseLocation
            Task { @MainActor in self?.updateHover(at: location) }
        }
    }

    deinit {
        autoCollapseTask?.cancel()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }
    }

    private func refresh(animated: Bool = true) {
        let agentSession = settings.agentNotchEnabled ? store.primarySession : nil
        let musicTrack = settings.musicNotchEnabled ? store.nowPlayingStore.track : nil
        store.nowPlayingStore.setProgressTrackingEnabled(
            isHoverExpanded && agentSession == nil && musicTrack != nil
        )
        guard agentSession != nil || musicTrack != nil else {
            isHoverExpanded = false
            isAutoExpanded = false
            hoverFrame = .zero
            autoCollapseTask?.cancel()
            store.nowPlayingStore.setProgressTrackingEnabled(false)
            panel.orderOut(nil)
            return
        }

        let screen = preferredScreen()
        let notchHeight = physicalNotchHeight(on: screen)
        let notchWidth = physicalNotchWidth(on: screen)
        let hasNotch = notchHeight > 0
        let compactWidth: CGFloat
        if hasNotch {
            if agentSession?.state == .waitingForApproval {
                compactWidth = notchWidth + 140
            } else if musicTrack != nil {
                // Keep the resting music pill close to the physical notch:
                // roughly 40 pt for the artwork wing and 40 pt for the meter.
                compactWidth = notchWidth + 80
            } else {
                compactWidth = notchWidth + 96
            }
        } else {
            compactWidth = musicTrack == nil ? 300 : 320
        }
        let expandedWidth: CGFloat = agentSession == nil ? 340 : 440
        let width: CGFloat = isExpanded ? expandedWidth : compactWidth
        let expandedTopInset = hasNotch && isExpanded && agentSession == nil
            ? expandedContentTopInset(notchHeight: notchHeight, notchWidth: notchWidth)
            : 0
        let contentHeight: CGFloat
        if hasNotch {
            contentHeight = isExpanded
                ? expandedTopInset + (agentSession == nil ? musicExpandedContentHeight : expandedContentHeight)
                : 0
        } else {
            contentHeight = agentSession == nil ? musicExpandedContentHeight : (isExpanded ? expandedContentHeight : 42)
        }
        let height = notchHeight + contentHeight
        let x = screen.frame.midX - width / 2
        let y = screen.frame.maxY - height
        let frame = NSRect(x: x, y: y, width: width, height: height)
        // Use the intended frame for hit testing. During an AppKit frame
        // animation panel.frame may briefly describe an intermediate size,
        // which can otherwise cancel the hover that started the expansion.
        hoverFrame = frame
        presentation.notchHeight = notchHeight
        presentation.notchWidth = notchWidth
        presentation.expandedContentTopInset = expandedTopInset
        presentation.isExpanded = isExpanded
        presentation.showsMusic = agentSession == nil && musicTrack != nil

        panel.level = hasNotch ? .mainMenu + 3 : .statusBar
        if panel.isVisible, animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.26
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
            panel.orderFrontRegardless()
        }
    }

    private func preferredScreen() -> NSScreen {
        NSScreen.screens.first(where: {
            $0.safeAreaInsets.top > 0 || $0.auxiliaryTopLeftArea != nil
        }) ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func physicalNotchHeight(on screen: NSScreen) -> CGFloat {
        let auxiliaryHeight = max(
            screen.auxiliaryTopLeftArea?.height ?? 0,
            screen.auxiliaryTopRightArea?.height ?? 0
        )
        return max(screen.safeAreaInsets.top, auxiliaryHeight)
    }

    private func physicalNotchWidth(on screen: NSScreen) -> CGFloat {
        guard physicalNotchHeight(on: screen) > 0 else { return 0 }
        if let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let measuredWidth = screen.frame.width - left.width - right.width
            if measuredWidth > 0 {
                return min(max(measuredWidth, 160), 260)
            }
        }
        return 200
    }

    private var expandedContentHeight: CGFloat {
        let visibleSessionCount = min(store.sessions.count, 3)
        return 55 + CGFloat(visibleSessionCount * 30) + (visibleSessionCount > 0 ? 9 : 0)
    }

    private var musicExpandedContentHeight: CGFloat {
        100
    }

    private func expandedContentTopInset(notchHeight: CGFloat, notchWidth: CGFloat) -> CGFloat {
        // Different MacBook panels report slightly different safe-area and
        // auxiliary widths. Use the physical notch measurements to leave a
        // small visual clearance below the camera housing instead of relying
        // on a single hard-coded model value.
        let heightBasedInset = notchHeight * 0.16
        let widthAdjustment = max(0, notchWidth - 200) * 0.025
        return min(max(heightBasedInset + widthAdjustment, 6), 14)
    }

    private var isExpanded: Bool {
        isHoverExpanded || isAutoExpanded
    }

    private func setHoverExpanded(_ expanded: Bool) {
        guard isHoverExpanded != expanded else { return }
        isHoverExpanded = expanded
        refresh()
    }

    private func updateHover(at screenLocation: NSPoint) {
        // NSRect excludes its maximum X/Y edge. The pointer can report a
        // coordinate exactly on the display's top edge, so include a small
        // tolerance around the target frame (including behind the camera).
        let hoverToleranceFrame = hoverFrame.insetBy(dx: -2, dy: -4)
        let hovering = panel.isVisible && hoverToleranceFrame.contains(screenLocation)
        setHoverExpanded(hovering)
    }

    private func musicTrackDidChange(_ track: NowPlayingTrack?, enabled: Bool) {
        let newID = enabled ? track?.id : nil
        let didChange = newID != nil && newID != lastMusicTrackID
        lastMusicTrackID = newID

        if didChange, store.primarySession == nil {
            showMusicChangePreview()
        } else {
            refresh()
        }
    }

    private func showMusicChangePreview() {
        autoCollapseTask?.cancel()
        isAutoExpanded = true
        NSLog("[AirSentry Media] Expanding notch for track change")
        refresh()

        autoCollapseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(2500))
            guard !Task.isCancelled else { return }
            self?.isAutoExpanded = false
            self?.refresh()
        }
    }

    private func collapse() {
        autoCollapseTask?.cancel()
        isAutoExpanded = false
        isHoverExpanded = false
        store.nowPlayingStore.setProgressTrackingEnabled(false)
        refresh()
    }
}

private final class AgentNotchPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
