import Foundation
import KWWKLauncherCore
import Testing

@Suite("Launcher workflows")
struct LauncherWorkflowTests {
    @Test
    func loadsArrayAndDocumentJSONFormats() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let arrayURL = directory.appendingPathComponent("array.json")
        let documentURL = directory.appendingPathComponent("document.json")

        try """
        [
          {
            "id": "review-and-test",
            "title": "Review And Test",
            "subtitle": "Ask KWWK then run tests",
            "keywords": ["review"],
            "model": "gpt-5.4",
            "thinking": "high",
            "context1m": true,
            "steps": [
              { "title": "Review", "prompt": "Review {query} in {workspace}" },
              { "title": "Test", "kind": "shell", "command": "swift test --filter {previousOutput}" }
            ]
          }
        ]
        """.write(to: arrayURL, atomically: true, encoding: .utf8)

        try """
        {
          "workflows": [
            {
              "id": "ship-summary",
              "title": "Ship Summary",
              "icon": "checklist",
              "steps": [
                { "kind": "prompt", "template": "Summarize {clipboard}" }
              ]
            }
          ]
        }
        """.write(to: documentURL, atomically: true, encoding: .utf8)

        let arrayWorkflow = try #require(LauncherWorkflowIndex.load(from: arrayURL).first)
        let documentWorkflow = try #require(LauncherWorkflowIndex.load(from: documentURL).first)

        #expect(arrayWorkflow.id == "review-and-test")
        #expect(arrayWorkflow.steps[0].kind == .prompt)
        #expect(arrayWorkflow.steps[1].kind == .shell)
        #expect(arrayWorkflow.steps[1].template == "swift test --filter {previousOutput}")
        #expect(arrayWorkflow.model == "gpt-5.4")
        #expect(arrayWorkflow.thinking == .high)
        #expect(arrayWorkflow.context1m == true)
        #expect(documentWorkflow.systemImage == "checklist")
        #expect(documentWorkflow.steps[0].template == "Summarize {clipboard}")
    }

    @Test
    func savedWorkflowFactoriesCreateOneStepAutomationSeeds() throws {
        let prompt = try #require(LauncherWorkflowIndex.workflow(
            fromPrompt: "Summarize the current project"
        ))
        let shell = try #require(LauncherWorkflowIndex.workflow(
            fromShellCommand: "git status --short"
        ))

        #expect(prompt.id == "saved-summarize-the-current-project")
        #expect(prompt.title == "Summarize The Current Project")
        #expect(prompt.subtitle == "Saved prompt workflow")
        #expect(prompt.systemImage == "sparkles")
        #expect(prompt.keywords.contains("workflow"))
        #expect(prompt.steps == [
            LauncherWorkflowStep(
                id: "ask-kwwk",
                title: "Ask KWWK",
                kind: .prompt,
                template: "Summarize the current project"
            ),
        ])

        #expect(shell.id == "saved-git-status-short")
        #expect(shell.title == "Git Status Short")
        #expect(shell.subtitle == "Saved shell workflow")
        #expect(shell.systemImage == "terminal")
        #expect(shell.steps == [
            LauncherWorkflowStep(
                id: "run-shell",
                title: "Run Shell",
                kind: .shell,
                template: "git status --short"
            ),
        ])
    }

    @Test
    func upsertWritesAndReplacesWorkflows() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("workflows.json")
        let first = try #require(LauncherWorkflowIndex.workflow(fromPrompt: "Review diff"))
        let replacement = LauncherWorkflow(
            id: first.id,
            title: "Review Diff Carefully",
            subtitle: "Replacement",
            steps: [
                LauncherWorkflowStep(
                    id: "review",
                    title: "Review",
                    kind: .prompt,
                    template: "Review carefully"
                ),
            ]
        )

        try LauncherWorkflowIndex.upsert(first, to: url)
        try LauncherWorkflowIndex.upsert(replacement, to: url)
        let loaded = LauncherWorkflowIndex.load(from: url)

        #expect(loaded == [replacement])
    }

    @Test
    func rendersTemplatesWithContextAndPreviousOutput() throws {
        let workflow = LauncherWorkflow(
            id: "review-and-test",
            title: "Review And Test",
            keywords: ["review"],
            steps: [
                LauncherWorkflowStep(
                    id: "review",
                    title: "Review",
                    kind: .prompt,
                    template: "Review {query}\nClipboard: {clipboard}\nWorkspace: {workspace}"
                ),
                LauncherWorkflowStep(
                    id: "test",
                    title: "Test",
                    kind: .shell,
                    template: "printf %s {previousOutput}"
                ),
            ]
        )
        let context = LauncherContextSnapshot(
            workingDirectory: "/Users/f/project",
            finderSelectionPaths: ["/Users/f/project/Package.swift"],
            frontmostApplicationName: "Ghostty"
        )

        let prompt = workflow.renderedTemplate(
            for: workflow.steps[0],
            query: "review staged changes",
            clipboard: "diff --git",
            context: context
        )
        let shell = workflow.renderedTemplate(
            for: workflow.steps[1],
            query: "review staged changes",
            context: context,
            previousOutput: "KWWKLauncherCoreTests"
        )

        #expect(prompt.contains("Review staged changes"))
        #expect(prompt.contains("diff --git"))
        #expect(prompt.contains("/Users/f/project"))
        #expect(shell == "printf %s KWWKLauncherCoreTests")
    }

    @Test
    func rendersShellQuotedTemplatePlaceholders() throws {
        let workflow = LauncherWorkflow(
            id: "quoted",
            title: "Quoted",
            keywords: ["run"],
            steps: [
                LauncherWorkflowStep(
                    id: "shell",
                    title: "Shell",
                    kind: .shell,
                    template: "printf %s {query:q} && open {workspace:q} && swift test --filter {previousOutput:q}"
                ),
            ]
        )
        let context = LauncherContextSnapshot(workingDirectory: "/Users/f/My Project")

        let shell = workflow.renderedTemplate(
            for: workflow.steps[0],
            query: "run failing test",
            context: context,
            previousOutput: "KWWKLauncherCoreTests/test name"
        )

        #expect(shell == "printf %s 'failing test' && open '/Users/f/My Project' && swift test --filter 'KWWKLauncherCoreTests/test name'")
    }

    @Test
    func templateRenderingDoesNotReexpandPlaceholderTextFromValues() {
        let workflow = LauncherWorkflow(
            id: "literal",
            title: "Literal",
            steps: [
                LauncherWorkflowStep(
                    id: "shell",
                    title: "Shell",
                    kind: .shell,
                    template: "printf %s {previousOutput:q}"
                ),
            ]
        )

        let shell = workflow.renderedTemplate(
            for: workflow.steps[0],
            query: "literal",
            context: LauncherContextSnapshot(workingDirectory: "/tmp/project"),
            previousOutput: "{workspace}"
        )

        #expect(shell == "printf %s '{workspace}'")
    }

    @Test
    func workflowRuntimeOverridesResolveAgainstLauncherDefaults() {
        let workflow = LauncherWorkflow(
            id: "review",
            title: "Review",
            model: "  gpt-5.4  ",
            thinking: .xhigh,
            context1m: false,
            steps: [
                LauncherWorkflowStep(id: "review", title: "Review", kind: .prompt, template: "Review {query}"),
            ]
        )
        let inherited = LauncherWorkflow(
            id: "default",
            title: "Default",
            steps: [
                LauncherWorkflowStep(id: "review", title: "Review", kind: .prompt, template: "Review {query}"),
            ]
        )

        #expect(workflow.resolvedModel(default: "claude-sonnet-4-5") == "gpt-5.4")
        #expect(workflow.resolvedThinking(default: .medium) == .xhigh)
        #expect(workflow.resolvedContext1M(default: true) == false)
        #expect(workflow.runtimeDescription.contains("Model: gpt-5.4"))
        #expect(workflow.runtimeDescription.contains("Thinking: xhigh"))
        #expect(workflow.runtimeDescription.contains("1M context: disabled"))
        #expect(inherited.resolvedModel(default: "claude-sonnet-4-5") == "claude-sonnet-4-5")
        #expect(inherited.resolvedThinking(default: .low) == .low)
        #expect(inherited.resolvedContext1M(default: true) == true)
        #expect(inherited.runtimeDescription == "Uses launcher AI defaults")
    }

    @Test
    func promptStepInvocationUsesWorkflowRuntimeAndLauncherDefaults() {
        let workflow = LauncherWorkflow(
            id: "review",
            title: "Review",
            model: "gpt-5.4",
            thinking: .high,
            context1m: true,
            steps: [
                LauncherWorkflowStep(id: "review", title: "Review", kind: .prompt, template: "Review {query}"),
            ]
        )

        let invocation = workflow.invocation(
            for: workflow.steps[0],
            renderedTemplate: "Review staged changes",
            query: "review staged changes",
            executable: "/tmp/kwwk helper",
            defaultThinking: .low,
            defaultModel: "claude-sonnet-4-5",
            defaultContext1M: false,
            workingDirectory: "/Users/f/My Project"
        )

        #expect(invocation.executable == "/tmp/kwwk helper")
        #expect(invocation.arguments == [
            "--thinking", "high",
            "--model", "gpt-5.4",
            "--context-1m",
            "-p", "-",
        ])
        #expect(invocation.stdin == "Review staged changes")
        #expect(invocation.workingDirectory == "/Users/f/My Project")
    }

    @Test
    func shellStepInvocationCarriesLauncherEnvironmentAndPreviousOutput() {
        let workflow = LauncherWorkflow(
            id: "test",
            title: "Test",
            steps: [
                LauncherWorkflowStep(
                    id: "shell",
                    title: "Shell",
                    kind: .shell,
                    template: "swift test --filter {previousOutput:q}"
                ),
            ]
        )
        let context = LauncherContextSnapshot(workingDirectory: "/Users/f/My Project")
        let rendered = workflow.renderedTemplate(
            for: workflow.steps[0],
            query: "test failing case",
            context: context,
            previousOutput: "KWWKLauncherCoreTests/test name"
        )

        let invocation = workflow.invocation(
            for: workflow.steps[0],
            renderedTemplate: rendered,
            query: "test failing case",
            workingDirectory: nil,
            context: context,
            previousOutput: "KWWKLauncherCoreTests/test name"
        )

        #expect(invocation.executable == "/bin/zsh")
        #expect(invocation.arguments == ["-lc", "swift test --filter 'KWWKLauncherCoreTests/test name'"])
        #expect(invocation.workingDirectory == "/Users/f/My Project")
        #expect(invocation.environment["KWWK_LAUNCHER_QUERY"] == "test failing case")
        #expect(invocation.environment["KWWK_LAUNCHER_CWD"] == "/Users/f/My Project")
        #expect(invocation.environment["KWWK_LAUNCHER_WORKSPACE"] == "/Users/f/My Project")
        #expect(invocation.environment["KWWK_LAUNCHER_PREVIOUS_OUTPUT"] == "KWWKLauncherCoreTests/test name")
    }

    @Test
    func workflowStepOutputCombinesTrimmedStdoutAndStderr() {
        let result = KWWKCLIRunResult(
            invocation: KWWKCLIInvocation(executable: "/bin/echo", arguments: []),
            exitCode: 0,
            stdout: "answer\n",
            stderr: "warning\n"
        )

        #expect(LauncherWorkflow.stepOutput(result) == "answer\nwarning")
    }

    @Test
    func workflowCommandsAreSearchableAndExportable() throws {
        let workflow = LauncherWorkflow(
            id: "review-and-test",
            title: "Review And Test",
            subtitle: "Ask then test",
            keywords: ["ship"],
            steps: [
                LauncherWorkflowStep(id: "review", title: "Review", kind: .prompt, template: "Review {query}"),
            ]
        )
        let command = try #require(LauncherWorkflowIndex.commands(for: [workflow]).first)

        #expect(command.id == "workflow:review-and-test")
        #expect(command.category == .workflow)
        #expect(command.action == .runWorkflow(workflow))
        #expect(LauncherCommandFilter.filter([command], query: "@workflows ship").first?.id == command.id)
        #expect(LauncherActionCatalog.primaryTitle(for: command) == "Run Workflow")
        #expect(LauncherActionCatalog.launcherCommand(
            for: command,
            query: "ship staged changes"
        ) == "kwwk launcher --command workflow:review-and-test --run -- 'staged changes'")
    }

    @Test
    func actionCatalogExposesRenderedWorkflowContext() throws {
        let workflow = LauncherWorkflow(
            id: "ship",
            title: "Ship",
            model: "gpt-5.4",
            thinking: .high,
            context1m: true,
            steps: [
                LauncherWorkflowStep(id: "summary", title: "Summary", kind: .prompt, template: "Summarize {query}"),
                LauncherWorkflowStep(id: "test", title: "Test", kind: .shell, template: "swift test"),
            ]
        )
        let command = try #require(LauncherWorkflowIndex.commands(for: [workflow]).first)
        let actions = LauncherActionCatalog.actions(
            for: command,
            isFavorite: false,
            query: "ship current diff",
            executable: "/Applications/KWWKLauncher.app/Contents/MacOS/kwwk",
            workingDirectory: "/Users/f/My Project"
        )

        #expect(actions.first { $0.id == "copy-workflow-id" }?.kind == .copyText("ship"))
        #expect(actions.contains {
            guard case .copyText(let value) = $0.kind else { return false }
            return $0.id == "copy-workflow-preview"
                && value.contains("Summarize current diff")
                && value.contains("swift test")
        })
        #expect(actions.first { $0.id == "copy-workflow-runtime" }?.kind == .copyText(
            "Model: gpt-5.4\nThinking: high\n1M context: enabled"
        ))
        #expect(
            actions.first { $0.id == "open-workflow-terminal" }?.kind == .openTerminalCommand([
                "cd '/Users/f/My Project' &&",
                "/Applications/KWWKLauncher.app/Contents/MacOS/kwwk",
                "workflow ship -- 'current diff'",
            ].joined(separator: " "))
        )
        #expect(actions.first { $0.id == "copy-workflow-cli-command" }?.kind == .copyText(
            "kwwk workflow ship -- 'current diff'"
        ))
    }

    @Test
    func workflowExportRecordsIncludeReplayableCLICommands() throws {
        let workflow = LauncherWorkflow(
            id: "ship",
            title: "Ship",
            subtitle: "Review then test",
            systemImage: "shippingbox",
            keywords: ["release"],
            model: "gpt-5.4",
            thinking: .high,
            context1m: false,
            steps: [
                LauncherWorkflowStep(id: "review", title: "Review", kind: .prompt, template: "Review {query}"),
                LauncherWorkflowStep(id: "test", title: "Test", kind: .shell, template: "swift test"),
            ]
        )

        let record = try #require(LauncherWorkflowExport.records(for: [workflow]).first)
        let json = try LauncherWorkflowExport.json(for: [workflow], query: "ship current diff")

        #expect(workflow.cliCommand() == "kwwk workflow ship -- '<query>'")
        #expect(
            workflow.cliCommand(query: "ship current diff", executable: "/tmp/kwwk helper")
                == "'/tmp/kwwk helper' workflow ship -- 'current diff'"
        )
        #expect(
            workflow.terminalCommand(query: "ship current diff", workingDirectory: "/Users/f/My Project")
                == "cd '/Users/f/My Project' && kwwk workflow ship -- 'current diff'"
        )
        #expect(record.id == "ship")
        #expect(record.subtitle == "Review then test")
        #expect(record.systemImage == "shippingbox")
        #expect(record.keywords == ["release"])
        #expect(record.stepCount == 2)
        #expect(record.runtime == "Model: gpt-5.4\nThinking: high\n1M context: disabled")
        #expect(record.cliCommand == "kwwk workflow ship -- '<query>'")
        #expect(json.contains("\"cliCommand\" : \"kwwk workflow ship -- 'current diff'\""))
        #expect(json.contains("\"stepCount\" : 2"))
    }

    @Test
    func workflowFileCommandsExposeExpectedPrimaryTitles() throws {
        let reveal = try #require(LauncherCommandCatalog.defaults.first { $0.id == "reveal-workflows" })
        let reload = try #require(LauncherCommandCatalog.defaults.first { $0.id == "reload-workflows" })

        #expect(LauncherActionCatalog.primaryTitle(for: reveal) == "Reveal")
        #expect(LauncherActionCatalog.primaryTitle(for: reload) == "Reload")
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
