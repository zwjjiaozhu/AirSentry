import Foundation

struct AgentHookInstallationStatus {
    var codexInstalled = false
    var claudeInstalled = false
    var lastError: String?

    var summary: String {
        if let lastError { return lastError }
        if codexInstalled && claudeInstalled { return "Codex 与 Claude Hooks 已安装" }
        if codexInstalled { return "Codex Hooks 已安装" }
        if claudeInstalled { return "Claude Hooks 已安装" }
        return "尚未安装 Hooks"
    }
}

final class AgentHookManager {
    private let fileManager = FileManager.default
    private let marker = "airsentry-agent-hook"

    private var supportDirectory: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AirSentry", isDirectory: true)
    }

    private var bridgeURL: URL {
        supportDirectory.appendingPathComponent("airsentry-hook.py")
    }

    func status() -> AgentHookInstallationStatus {
        AgentHookInstallationStatus(
            codexInstalled: containsAirSentryHook(at: codexHooksURL),
            claudeInstalled: containsAirSentryHook(at: claudeSettingsURL)
        )
    }

    func install(token: String, codex: Bool, claude: Bool) throws -> AgentHookInstallationStatus {
        try fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        try bridgeScript(token: token).write(to: bridgeURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: bridgeURL.path)

        if codex {
            try installHooks(at: codexHooksURL, provider: .codex)
        }
        if claude {
            try installHooks(at: claudeSettingsURL, provider: .claude)
        }
        return status()
    }

    func uninstall() throws -> AgentHookInstallationStatus {
        try removeHooks(at: codexHooksURL)
        try removeHooks(at: claudeSettingsURL)
        try? fileManager.removeItem(at: bridgeURL)
        return status()
    }

    private var codexHooksURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("hooks.json")
    }

    private var claudeSettingsURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    private func containsAirSentryHook(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return false }
        return text.contains(marker)
    }

    private func installHooks(at url: URL, provider: AgentProvider) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var root = try readJSONObject(at: url)
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        for event in hookEvents {
            var groups = hooks[event] as? [[String: Any]] ?? []
            groups.removeAll { groupContainsMarker($0) }
            groups.append([
                "hooks": [[
                    "type": "command",
                    "command": hookCommand(provider: provider, event: event),
                    "timeout": 5
                ]]
            ])
            hooks[event] = groups
        }

        root["hooks"] = hooks
        try writeJSONObject(root, to: url)
    }

    private func removeHooks(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        var root = try readJSONObject(at: url)
        guard var hooks = root["hooks"] as? [String: Any] else { return }

        for key in hooks.keys {
            guard var groups = hooks[key] as? [[String: Any]] else { continue }
            groups.removeAll { groupContainsMarker($0) }
            if groups.isEmpty {
                hooks.removeValue(forKey: key)
            } else {
                hooks[key] = groups
            }
        }

        root["hooks"] = hooks
        try writeJSONObject(root, to: url)
    }

    private var hookEvents: [String] {
        ["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "Stop"]
    }

    private func hookCommand(provider: AgentProvider, event: String) -> String {
        let escapedPath = bridgeURL.path.replacingOccurrences(of: "'", with: "'\\''")
        return "/usr/bin/python3 '\(escapedPath)' --marker \(marker) --provider \(provider.rawValue) --event \(event)"
    }

    private func groupContainsMarker(_ group: [String: Any]) -> Bool {
        guard let handlers = group["hooks"] as? [[String: Any]] else { return false }
        return handlers.contains { ($0["command"] as? String)?.contains(marker) == true }
    }

    private func readJSONObject(at url: URL) throws -> [String: Any] {
        guard fileManager.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [:] }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return root
    }

    private func writeJSONObject(_ root: [String: Any], to url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            let backup = url.appendingPathExtension("airsentry-backup")
            try? fileManager.removeItem(at: backup)
            try fileManager.copyItem(at: url, to: backup)
        }
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }

    private func bridgeScript(token: String) -> String {
        """
        #!/usr/bin/python3
        # airsentry-agent-hook
        import argparse
        import datetime
        import json
        import os
        import sys
        import urllib.request
        import uuid

        parser = argparse.ArgumentParser(add_help=False)
        parser.add_argument("--marker")
        parser.add_argument("--provider", required=True)
        parser.add_argument("--event", required=True)
        args, _ = parser.parse_known_args()

        try:
            payload = json.load(sys.stdin)
        except Exception:
            payload = {}

        event_name = args.event
        if event_name == "PermissionRequest":
            state = "waitingForApproval"
        elif event_name == "Stop":
            state = "completed"
        else:
            state = "working"

        tool = payload.get("tool_name") or payload.get("toolName")
        session = str(payload.get("session_id") or payload.get("sessionId") or payload.get("conversation_id") or (args.provider + "-default"))
        cwd = payload.get("cwd") or os.getcwd()
        project = os.path.basename(cwd.rstrip(os.sep)) if cwd else None
        body = {
            "id": str(uuid.uuid4()),
            "provider": args.provider,
            "sessionID": session,
            "project": project,
            "workingDirectory": cwd,
            "state": state,
            "action": tool or event_name,
            "timestamp": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        }
        data = json.dumps(body).encode("utf-8")
        request = urllib.request.Request(
            "http://127.0.0.1:\(AgentEventServer.port)/events",
            data=data,
            method="POST",
            headers={"Content-Type": "application/json", "X-AirSentry-Token": "\(token)"},
        )
        try:
            urllib.request.urlopen(request, timeout=1).close()
        except Exception:
            pass
        """
    }
}
