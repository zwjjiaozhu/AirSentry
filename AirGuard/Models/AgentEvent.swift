import Foundation

enum AgentProvider: String, Codable, CaseIterable, Identifiable {
    case codex
    case claude

    var id: String { rawValue }

    var title: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        }
    }
}

enum AgentActivityState: String, Codable {
    case working
    case waitingForApproval
    case completed
    case failed

    var priority: Int {
        switch self {
        case .waitingForApproval: 4
        case .failed: 3
        case .working: 2
        case .completed: 1
        }
    }
}

struct AgentEvent: Codable, Identifiable {
    let id: UUID
    let provider: AgentProvider
    let sessionID: String
    let project: String?
    let workingDirectory: String?
    let state: AgentActivityState
    let action: String?
    let timestamp: Date

    init(
        id: UUID = UUID(),
        provider: AgentProvider,
        sessionID: String,
        project: String? = nil,
        workingDirectory: String? = nil,
        state: AgentActivityState,
        action: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.provider = provider
        self.sessionID = sessionID
        self.project = project
        self.workingDirectory = workingDirectory
        self.state = state
        self.action = action
        self.timestamp = timestamp
    }
}

struct AgentSession: Identifiable {
    let id: String
    let provider: AgentProvider
    var project: String?
    var workingDirectory: String?
    var state: AgentActivityState
    var action: String?
    var updatedAt: Date
}
