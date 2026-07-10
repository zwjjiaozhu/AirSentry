import Foundation
import SwiftUI

enum AIUsageProviderID: String, CaseIterable, Identifiable {
    case codex
    case claude
    case qoder
    case cursor
    case windsurf
    case copilot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        case .qoder: "Qoder"
        case .cursor: "Cursor"
        case .windsurf: "Windsurf"
        case .copilot: "GitHub Copilot"
        }
    }

    var planName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude Pro"
        case .qoder: "Qoder"
        case .cursor: "Cursor Pro"
        case .windsurf: "Windsurf"
        case .copilot: "Copilot"
        }
    }

    var systemImage: String {
        switch self {
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .claude: "sparkle"
        case .qoder: "cube.transparent"
        case .cursor: "cursorarrow.rays"
        case .windsurf: "wind"
        case .copilot: "person.crop.circle.badge.checkmark"
        }
    }

    var accentColor: Color {
        switch self {
        case .codex: .blue
        case .claude: .orange
        case .qoder: .indigo
        case .cursor: .purple
        case .windsurf: .cyan
        case .copilot: .green
        }
    }
}

struct AITokenUsage: Equatable {
    var inputTokens: Int
    var cachedInputTokens: Int
    var outputTokens: Int
    var reasoningOutputTokens: Int
    var totalTokens: Int

    static let empty = AITokenUsage(
        inputTokens: 0,
        cachedInputTokens: 0,
        outputTokens: 0,
        reasoningOutputTokens: 0,
        totalTokens: 0
    )
}

struct AIUsageRateLimit: Identifiable, Equatable {
    enum WindowKind: String {
        case primary
        case secondary
    }

    let id = UUID()
    var kind: WindowKind
    var usedPercent: Double?
    var windowMinutes: Int?
    var resetsAt: Date?
    var observedAt: Date?

    var remainingPercent: Double? {
        guard let usedPercent else { return nil }
        return max(0, 100 - usedPercent)
    }
}

struct AIUsageSnapshot: Identifiable, Equatable {
    let id: AIUsageProviderID
    var providerName: String { id.title }
    var planName: String { id.planName }
    var systemImage: String { id.systemImage }
    var accentColor: Color { id.accentColor }

    var isDetected: Bool
    var latestEventAt: Date?
    var currentUsage: AITokenUsage?
    var totalUsage: AITokenUsage?
    var rateLimits: [AIUsageRateLimit]
    var sourceFileCount: Int
    var sourceDescription: String?
    var statusMessage: String?

    static func empty(_ id: AIUsageProviderID) -> AIUsageSnapshot {
        AIUsageSnapshot(
            id: id,
            isDetected: false,
            latestEventAt: nil,
            currentUsage: nil,
            totalUsage: nil,
            rateLimits: [],
            sourceFileCount: 0,
            sourceDescription: nil,
            statusMessage: "未发现本地记录"
        )
    }

    var preferredRateLimit: AIUsageRateLimit? {
        rateLimits.first { $0.kind == .primary && $0.usedPercent != nil } ??
        rateLimits.first { $0.usedPercent != nil }
    }

    var displayUsedPercent: Double? {
        preferredRateLimit?.usedPercent
    }

    var displayRemainingPercent: Double? {
        preferredRateLimit?.remainingPercent
    }

    var displayResetDate: Date? {
        preferredRateLimit?.resetsAt
    }

    var displayTokenTotal: Int? {
        currentUsage?.totalTokens ?? totalUsage?.totalTokens
    }
}

struct AIUsageOverview: Equatable {
    var snapshots: [AIUsageSnapshot]
    var scannedAt: Date?
    var errorMessage: String?

    static let empty = AIUsageOverview(snapshots: AIUsageProviderID.allCases.map(AIUsageSnapshot.empty), scannedAt: nil, errorMessage: nil)

    var detectedSnapshots: [AIUsageSnapshot] {
        snapshots.filter(\.isDetected)
    }

    var bestSnapshot: AIUsageSnapshot? {
        snapshots
            .filter { $0.displayRemainingPercent != nil }
            .sorted {
                ($0.latestEventAt ?? .distantPast) > ($1.latestEventAt ?? .distantPast)
            }
            .first
    }

    var totalCurrentTokens: Int {
        snapshots.compactMap(\.currentUsage?.totalTokens).reduce(0, +)
    }

    var nextResetAt: Date? {
        snapshots
            .flatMap(\.rateLimits)
            .compactMap(\.resetsAt)
            .filter { $0 > Date() }
            .min()
    }
}
