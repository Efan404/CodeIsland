import XCTest
@testable import CodeIsland

final class ConfigInstallerTests: XCTestCase {
    func testRemoveManagedHookEntriesAlsoPrunesLegacyVibeIslandHooks() throws {
        let hooks: [String: Any] = [
            "SessionEnd": [
                [
                    "hooks": [
                        [
                            "command": "/Users/test/.vibe-island/bin/vibe-island-bridge --source claude",
                            "type": "command",
                        ],
                    ],
                ],
                [
                    "matcher": "",
                    "hooks": [
                        [
                            "command": "~/.claude/hooks/codeisland-hook.sh",
                            "timeout": 5,
                            "type": "command",
                        ],
                    ],
                ],
                [
                    "matcher": "",
                    "hooks": [
                        [
                            "async": true,
                            "command": "~/.claude/hooks/bark-notify.sh",
                            "timeout": 10,
                            "type": "command",
                        ],
                    ],
                ],
            ],
        ]

        let cleaned = ConfigInstaller.removeManagedHookEntries(from: hooks)
        let sessionEnd = try XCTUnwrap(cleaned["SessionEnd"] as? [[String: Any]])

        XCTAssertEqual(sessionEnd.count, 1)
        let remainingHooks = try XCTUnwrap(sessionEnd.first?["hooks"] as? [[String: Any]])
        XCTAssertEqual(remainingHooks.count, 1)
        XCTAssertEqual(remainingHooks.first?["command"] as? String, "~/.claude/hooks/bark-notify.sh")
    }

    // MARK: - Kimi Code CLI TOML hooks

    func testRemoveKimiHooksPreservesNonCodeIslandBlocks() {
        let toml = """
        default_model = "kimi-k2-5"

        [[hooks]]
        event = "Stop"
        command = "/Users/test/.codeisland/codeisland-bridge --source kimi"
        timeout = 5

        [[mcpServers]]
        name = "test"
        command = "npx"

        [[hooks]]
        event = "UserPromptSubmit"
        command = "echo hello"
        timeout = 1
        """

        let cleaned = ConfigInstaller.removeKimiHooks(from: toml)
        XCTAssertFalse(cleaned.contains("codeisland-bridge"))
        XCTAssertTrue(cleaned.contains("[[mcpServers]]"))
        XCTAssertTrue(cleaned.contains("echo hello"))
        XCTAssertTrue(cleaned.contains("default_model"))
    }

    func testContentsContainsKimiHookDetectsInstalledEvent() {
        let toml = """
        [[hooks]]
        event = "PreToolUse"
        command = "/Users/test/.codeisland/codeisland-bridge --source kimi"
        timeout = 5
        matcher = ".*"

        [[hooks]]
        event = "Stop"
        command = "/Users/test/.codeisland/codeisland-bridge --source kimi"
        timeout = 5
        """

        XCTAssertTrue(ConfigInstaller.contentsContainsKimiHook(toml, event: "PreToolUse"))
        XCTAssertTrue(ConfigInstaller.contentsContainsKimiHook(toml, event: "Stop"))
        XCTAssertFalse(ConfigInstaller.contentsContainsKimiHook(toml, event: "SessionStart"))
    }

    func testKimiHookFormatEvents() {
        let events = ConfigInstaller.defaultEvents(for: .kimi)
        let eventNames = events.map { $0.0 }
        XCTAssertTrue(eventNames.contains("UserPromptSubmit"))
        XCTAssertTrue(eventNames.contains("PreToolUse"))
        XCTAssertTrue(eventNames.contains("PostToolUse"))
        XCTAssertTrue(eventNames.contains("PostToolUseFailure"))
        XCTAssertFalse(eventNames.contains("PermissionRequest"), "Kimi does not support PermissionRequest")
        XCTAssertTrue(eventNames.contains("Stop"))
        XCTAssertTrue(eventNames.contains("SessionStart"))
        XCTAssertTrue(eventNames.contains("SessionEnd"))
        XCTAssertTrue(eventNames.contains("Notification"))
        XCTAssertTrue(eventNames.contains("PreCompact"))

        let notificationTimeout = events.first { $0.0 == "Notification" }?.1
        XCTAssertEqual(notificationTimeout, 600, "Kimi max timeout is 600")
    }

    /// Integration test: actually writes to ~/.kimi/config.toml and verifies hooks are installed.
    /// Must not conflict with other running CodeIsland instances.
    func testInstallKimiHooksIntegration() throws {
        let fm = FileManager.default
        let configPath = NSHomeDirectory() + "/.kimi/config.toml"

        // Backup existing config
        let backupPath = configPath + ".test.bak"
        if fm.fileExists(atPath: configPath) {
            try? fm.removeItem(atPath: backupPath)
            try? fm.copyItem(atPath: configPath, toPath: backupPath)
        }

        // Ensure bridge binary exists (needed for install detection)
        let codeislandDir = NSHomeDirectory() + "/.codeisland"
        if !fm.fileExists(atPath: codeislandDir) {
            try? fm.createDirectory(atPath: codeislandDir, withIntermediateDirectories: true)
        }

        // Install hooks
        let ok = ConfigInstaller.setEnabled(source: "kimi", enabled: true)
        XCTAssertTrue(ok, "Kimi hooks should install successfully")

        // Verify file contents
        let data = try XCTUnwrap(fm.contents(atPath: configPath))
        let contents = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(contents.contains("[[hooks]]"))
        XCTAssertTrue(contents.contains("event = \"PreToolUse\""))
        XCTAssertTrue(contents.contains("event = \"Stop\""))
        XCTAssertTrue(contents.contains("codeisland-bridge --source kimi"))
        XCTAssertFalse(contents.contains("hooks = []"), "Scalar hooks key should be removed to avoid TOML duplicate key error")

        // Check that install detection passes
        XCTAssertTrue(ConfigInstaller.isInstalled(source: "kimi"), "isInstalled should report true after install")

        // Uninstall and restore backup
        ConfigInstaller.setEnabled(source: "kimi", enabled: false)
        if fm.fileExists(atPath: backupPath) {
            try? fm.removeItem(atPath: configPath)
            try? fm.moveItem(atPath: backupPath, toPath: configPath)
        }
    }
}


