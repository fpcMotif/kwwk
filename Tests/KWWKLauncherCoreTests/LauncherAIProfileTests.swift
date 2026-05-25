import Foundation
import KWWKLauncherCore
import Testing

@Suite("Launcher AI profiles")
struct LauncherAIProfileTests {
    @Test
    func defaultProfilesArePaletteCommands() throws {
        let commands = LauncherAIProfileCatalog.defaultCommands()
        let fast = try #require(commands.first { $0.id == "ai-profile:fast" })
        let save = try #require(commands.first { $0.id == "save-current-ai-profile" })
        let reveal = try #require(commands.first { $0.id == "reveal-ai-profiles" })
        let reload = try #require(commands.first { $0.id == "reload-ai-profiles" })

        #expect(fast.title == "Use Fast AI Profile")
        #expect(fast.category == .model)
        #expect(fast.action == .applyAIProfile(LauncherAIProfile(
            id: "fast",
            title: "Use Fast AI Profile",
            subtitle: "Provider default model, low thinking",
            systemImage: "bolt",
            keywords: ["fast", "quick", "low", "cheap", "default"],
            thinking: .low
        )))
        #expect(save.action == .saveCurrentAIProfile)
        #expect(reveal.action == .revealAIProfilesFile)
        #expect(reload.action == .reloadAIProfiles)
    }

    @Test
    func loadsArrayAndDocumentJSONFormats() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let arrayURL = directory.appendingPathComponent("profiles-array.json")
        try writeFile(arrayURL, """
        [
          {
            "id": "spark",
            "title": "Spark",
            "model": "gpt-5.3-codex-spark",
            "thinking": "high"
          }
        ]
        """)

        let documentURL = directory.appendingPathComponent("profiles-document.json")
        try writeFile(documentURL, """
        {
          "profiles": [
            {
              "id": "deep",
              "title": "Deep Work",
              "subtitle": "Codex deep profile",
              "systemImage": "brain",
              "keywords": ["codex"],
              "model": "gpt-5.4",
              "thinking": "xhigh",
              "context1m": true
            }
          ]
        }
        """)

        let arrayProfile = try #require(LauncherAIProfileIndex.load(from: arrayURL).first)
        let documentProfile = try #require(LauncherAIProfileIndex.load(from: documentURL).first)

        #expect(arrayProfile.id == "spark")
        #expect(arrayProfile.thinking == .high)
        #expect(arrayProfile.context1m == false)
        #expect(documentProfile.id == "deep")
        #expect(documentProfile.systemImage == "brain")
        #expect(documentProfile.keywords == ["codex"])
        #expect(documentProfile.context1m == true)
    }

    @Test
    func currentSettingsBecomeProfileRecords() {
        let providerDefault = LauncherAIProfileIndex.profile(
            fromModel: "",
            thinking: .medium,
            context1m: false
        )
        let codexLong = LauncherAIProfileIndex.profile(
            fromModel: "gpt-5.4",
            thinking: .xhigh,
            context1m: true
        )

        #expect(providerDefault.id == "saved-provider-default-medium")
        #expect(providerDefault.title == "Saved Provider Default Medium Profile")
        #expect(providerDefault.subtitle == "Saved current launcher defaults")
        #expect(providerDefault.model == "")
        #expect(providerDefault.thinking == .medium)
        #expect(providerDefault.context1m == false)
        #expect(providerDefault.keywords.contains("provider-default"))

        #expect(codexLong.id == "saved-gpt-5-4-xhigh-1m-context")
        #expect(codexLong.title == "Saved gpt-5.4 XHigh Profile")
        #expect(codexLong.subtitle == "Saved current launcher defaults with 1M context")
        #expect(codexLong.systemImage == "text.page.badge.magnifyingglass")
        #expect(codexLong.model == "gpt-5.4")
        #expect(codexLong.thinking == .xhigh)
        #expect(codexLong.context1m == true)
    }

    @Test
    func upsertWritesAndReplacesProfiles() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("profiles.json")
        let first = LauncherAIProfileIndex.profile(
            fromModel: "gpt-5.4",
            thinking: .high,
            context1m: false
        )
        let replacement = LauncherAIProfile(
            id: first.id,
            title: "Saved Review Profile",
            model: "gpt-5.4",
            thinking: .xhigh,
            context1m: true
        )

        try LauncherAIProfileIndex.upsert(first, to: url)
        try LauncherAIProfileIndex.upsert(replacement, to: url)
        let loaded = LauncherAIProfileIndex.load(from: url)

        #expect(loaded == [replacement])
    }

    @Test
    func customProfilesBecomeSearchableCommandsAndSkipReservedIds() throws {
        let profiles = [
            LauncherAIProfile(id: "fast", title: "Override Fast", model: "ignored"),
            LauncherAIProfile(
                id: "review",
                title: "Review Profile",
                keywords: ["code review"],
                model: "gpt-5.4",
                thinking: .high
            ),
        ]

        let commands = LauncherAIProfileCatalog.commands(
            for: profiles,
            reservedCommandIds: LauncherAIProfileCatalog.defaultCommandIds
        )
        let command = try #require(commands.first)

        #expect(commands.map(\.id) == ["ai-profile:review"])
        #expect(command.category == .model)
        #expect(command.keywords.contains("code review"))
        #expect(command.action == .applyAIProfile(profiles[1]))
    }

    @Test
    func availableProfilesPreferDefaultsAndMatchCommandIds() throws {
        let profiles = LauncherAIProfileCatalog.availableProfiles(customProfiles: [
            LauncherAIProfile(id: "fast", title: "Custom Fast", model: "ignored"),
            LauncherAIProfile(
                id: "review",
                title: "Review Profile",
                model: "gpt-5.4",
                thinking: .high
            ),
        ])

        #expect(profiles.map(\.id) == ["fast", "codex-deep", "claude-long", "review"])
        #expect(profiles.first?.title == "Use Fast AI Profile")
        #expect(LauncherAIProfileCatalog.profile(
            matching: "ai-profile:review",
            customProfiles: profiles
        )?.model == "gpt-5.4")
        #expect(LauncherAIProfileCatalog.profile(
            matching: "missing",
            customProfiles: profiles
        ) == nil)
    }

    @Test
    func profileExportRecordsIncludeCLIReplay() throws {
        let profile = LauncherAIProfile(
            id: "deep review",
            title: "Deep Review",
            subtitle: "Review with Codex",
            systemImage: "brain",
            keywords: ["review"],
            model: "gpt-5.4",
            thinking: .xhigh,
            context1m: true
        )

        let record = try #require(LauncherAIProfileExport.records(for: [profile]).first)
        let table = LauncherAIProfileExport.table(for: [profile])
        let json = try LauncherAIProfileExport.json(for: [profile])

        #expect(record.id == "deep review")
        #expect(record.cliFlags == "--thinking xhigh --model gpt-5.4 --context-1m")
        #expect(record.headlessCommand == "kwwk --profile 'deep review' -p '<prompt>'")
        #expect(table == "deep review\tDeep Review\tgpt-5.4\txhigh\t1\t--thinking xhigh --model gpt-5.4 --context-1m")
        #expect(json.contains("\"headlessCommand\" : \"kwwk --profile 'deep review' -p '<prompt>'\""))
    }

    @Test
    func profileActionsExposeFlagsAndReplayableLauncherCommand() throws {
        let profile = LauncherAIProfile(
            id: "deep",
            title: "Deep Profile",
            model: "gpt-5.4",
            thinking: .xhigh,
            context1m: true
        )
        let command = LauncherAIProfileCatalog.command(for: profile)
        let actions = LauncherActionCatalog.actions(for: command, isFavorite: false)

        #expect(LauncherActionCatalog.primaryTitle(for: command) == "Apply Profile")
        #expect(actions.first { $0.id == "copy-profile-flags" }?.kind == .copyText(
            "--thinking xhigh --model gpt-5.4 --context-1m"
        ))
        #expect(actions.first { $0.id == "copy-headless-command" }?.kind == .copyText(
            "kwwk --thinking xhigh --model gpt-5.4 --context-1m -p '<prompt>'"
        ))
        #expect(actions.first { $0.id == "copy-launcher-command" }?.kind == .copyText(
            "kwwk launcher --command ai-profile:deep --run"
        ))
    }

    @Test
    func saveCurrentProfileCommandExportsActions() throws {
        let command = try #require(LauncherAIProfileCatalog.defaultCommands()
            .first { $0.id == "save-current-ai-profile" })
        let actions = LauncherActionCatalog.actions(for: command, isFavorite: false)

        #expect(LauncherActionCatalog.primaryTitle(for: command) == "Save Profile")
        #expect(actions.first { $0.id == "primary" }?.kind == .runPrimary)
        #expect(actions.first { $0.id == "copy-location" }?.kind == .copyText(
            "~/.kwwk/launcher/profiles.json"
        ))
        #expect(actions.first { $0.id == "copy-launcher-command" }?.kind == .copyText(
            "kwwk launcher --command save-current-ai-profile --run"
        ))
    }

    @Test
    func modelScopeFindsProfiles() throws {
        let results = LauncherCommandFilter.filter(
            LauncherCommandCatalog.defaults,
            query: "@models profile long"
        )

        #expect(results.first?.id == "ai-profile:claude-long")
        #expect(results.map(\.id) == ["ai-profile:claude-long"])
        #expect(results.allSatisfy { $0.category == .model })
    }

    @Test
    func modelScopeFindsProfileManagementCommands() {
        let results = LauncherCommandFilter.filter(
            LauncherCommandCatalog.defaults,
            query: "@models save current profile"
        )

        #expect(results.first?.id == "save-current-ai-profile")
        #expect(results.allSatisfy { $0.category == .model })
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeFile(_ url: URL, _ text: String) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
