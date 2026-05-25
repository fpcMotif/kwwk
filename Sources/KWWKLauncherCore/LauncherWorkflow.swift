import Foundation

public enum LauncherWorkflowStepKind: String, Codable, Sendable, Hashable {
    case prompt
    case shell

    var defaultTitle: String {
        switch self {
        case .prompt:
            return "Ask KWWK"
        case .shell:
            return "Run Shell"
        }
    }
}

public struct LauncherWorkflowStep: Codable, Identifiable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var kind: LauncherWorkflowStepKind
    public var template: String

    public init(
        id: String,
        title: String,
        kind: LauncherWorkflowStepKind,
        template: String
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.template = template
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let shellTemplate = try container.decodeIfPresent(String.self, forKey: .shell)
            ?? container.decodeIfPresent(String.self, forKey: .command)
        let promptTemplate = try container.decodeIfPresent(String.self, forKey: .promptTemplate)
            ?? container.decodeIfPresent(String.self, forKey: .prompt)
        kind = try container.decodeIfPresent(LauncherWorkflowStepKind.self, forKey: .kind)
            ?? (shellTemplate == nil ? .prompt : .shell)
        let templateValue = try container.decodeIfPresent(String.self, forKey: .template)
        template = promptTemplate
            ?? shellTemplate
            ?? templateValue
            ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title)
            ?? kind.defaultTitle
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? Self.slug(for: [title, kind.rawValue, template].joined(separator: " "))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(kind, forKey: .kind)
        try container.encode(template, forKey: .template)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case kind
        case template
        case prompt
        case promptTemplate
        case shell
        case command
    }

    private static func slug(for value: String) -> String {
        let scalars = value.lowercased().unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            return "-"
        }
        let collapsed = String(scalars)
            .split(separator: "-")
            .prefix(8)
            .joined(separator: "-")
        return collapsed.isEmpty ? "step" : collapsed
    }
}

public struct LauncherWorkflow: Codable, Identifiable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var systemImage: String
    public var keywords: [String]
    public var model: String?
    public var thinking: KWWKThinkingLevel?
    public var context1m: Bool?
    public var steps: [LauncherWorkflowStep]

    public init(
        id: String,
        title: String,
        subtitle: String = "",
        systemImage: String = "point.3.connected.trianglepath.dotted",
        keywords: [String] = [],
        model: String? = nil,
        thinking: KWWKThinkingLevel? = nil,
        context1m: Bool? = nil,
        steps: [LauncherWorkflowStep]
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.keywords = keywords
        self.model = model
        self.thinking = thinking
        self.context1m = context1m
        self.steps = steps
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        systemImage = try container.decodeIfPresent(String.self, forKey: .systemImage)
            ?? container.decodeIfPresent(String.self, forKey: .icon)
            ?? "point.3.connected.trianglepath.dotted"
        keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
        model = try container.decodeIfPresent(String.self, forKey: .model)
        thinking = try container.decodeIfPresent(KWWKThinkingLevel.self, forKey: .thinking)
        context1m = try container.decodeIfPresent(Bool.self, forKey: .context1m)
            ?? container.decodeIfPresent(Bool.self, forKey: .context1M)
        steps = try container.decode([LauncherWorkflowStep].self, forKey: .steps)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(subtitle, forKey: .subtitle)
        try container.encode(systemImage, forKey: .systemImage)
        try container.encode(keywords, forKey: .keywords)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encodeIfPresent(thinking, forKey: .thinking)
        try container.encodeIfPresent(context1m, forKey: .context1m)
        try container.encode(steps, forKey: .steps)
    }

    public func resolvedModel(default defaultModel: String?) -> String? {
        model?.trimmedNilIfEmpty ?? defaultModel?.trimmedNilIfEmpty
    }

    public func resolvedThinking(default defaultThinking: KWWKThinkingLevel) -> KWWKThinkingLevel {
        thinking ?? defaultThinking
    }

    public func resolvedContext1M(default defaultContext1M: Bool) -> Bool {
        context1m ?? defaultContext1M
    }

    public var runtimeDescription: String {
        let lines = [
            model?.trimmedNilIfEmpty.map { "Model: \($0)" },
            thinking.map { "Thinking: \($0.rawValue)" },
            context1m.map { "1M context: \($0 ? "enabled" : "disabled")" },
        ]
        .compactMap { $0 }
        return lines.isEmpty ? "Uses launcher AI defaults" : lines.joined(separator: "\n")
    }

    public func cliCommand(query: String = "", executable: String = "kwwk") -> String {
        let argument = argument(from: query)
        let queryArgument = argument.isEmpty ? "<query>" : argument
        return [
            KWWKShellCommand.quote(executable),
            "workflow",
            KWWKShellCommand.quote(id),
            "--",
            KWWKShellCommand.quote(queryArgument),
        ].joined(separator: " ")
    }

    public func terminalCommand(
        query: String = "",
        executable: String = "kwwk",
        workingDirectory: String? = nil
    ) -> String {
        KWWKShellCommand.terminalCommand(
            cliCommand(query: query, executable: executable),
            workingDirectory: workingDirectory
        )
    }

    public func argument(from query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let triggers = ([title] + keywords)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }

        for trigger in triggers {
            if trimmed.caseInsensitiveCompare(trigger) == .orderedSame {
                return ""
            }

            guard trimmed.count > trigger.count else { continue }
            let triggerEnd = trimmed.index(trimmed.startIndex, offsetBy: trigger.count)
            guard trimmed[..<triggerEnd].caseInsensitiveCompare(trigger) == .orderedSame,
                  trimmed[triggerEnd].isWhitespace
            else {
                continue
            }

            return String(trimmed[triggerEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmed
    }

    public func renderedTemplate(
        for step: LauncherWorkflowStep,
        query: String,
        clipboard: String = "",
        context: LauncherContextSnapshot = LauncherContextSnapshot(),
        previousOutput: String = ""
    ) -> String {
        let argument = argument(from: query)
        return Self.render(
            template: step.template,
            values: [
                "query": argument,
                "Query": argument,
                "argument": argument,
                "Argument": argument,
                "clipboard": clipboard,
                "Clipboard": clipboard,
                "workspace": context.workingDirectory ?? "",
                "Workspace": context.workingDirectory ?? "",
                "cwd": context.workingDirectory ?? "",
                "Cwd": context.workingDirectory ?? "",
                "finderSelection": context.finderSelectionPaths.joined(separator: "\n"),
                "FinderSelection": context.finderSelectionPaths.joined(separator: "\n"),
                "frontmostApp": context.frontmostApplicationName ?? "",
                "FrontmostApp": context.frontmostApplicationName ?? "",
                "previousOutput": previousOutput,
                "PreviousOutput": previousOutput,
            ]
        )
    }

    public func previewText(
        query: String,
        clipboard: String = "",
        context: LauncherContextSnapshot = LauncherContextSnapshot()
    ) -> String {
        let rendered = steps.enumerated().map { index, step in
            let value = renderedTemplate(
                for: step,
                query: query,
                clipboard: clipboard,
                context: context
            )
            return [
                "\(index + 1). \(step.title) (\(step.kind.rawValue))",
                value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            ]
            .compactMap { $0 }
            .joined(separator: "\n")
        }
        return ([subtitle.nilIfEmpty, runtimeDescription] + rendered)
            .compactMap { $0 }
            .joined(separator: "\n\n")
    }

    public func invocation(
        for step: LauncherWorkflowStep,
        renderedTemplate: String,
        query: String,
        executable: String = "kwwk",
        defaultThinking: KWWKThinkingLevel = .medium,
        defaultModel: String? = nil,
        defaultContext1M: Bool = false,
        workingDirectory: String? = nil,
        context: LauncherContextSnapshot = LauncherContextSnapshot(),
        previousOutput: String = ""
    ) -> KWWKCLIInvocation {
        switch step.kind {
        case .prompt:
            return KWWKCLIInvocation.headless(
                prompt: renderedTemplate,
                executable: executable,
                thinking: resolvedThinking(default: defaultThinking),
                model: resolvedModel(default: defaultModel),
                context1m: resolvedContext1M(default: defaultContext1M),
                workingDirectory: workingDirectory
            )
        case .shell:
            let resolvedWorkingDirectory = workingDirectory?.trimmedNilIfEmpty
                ?? context.workingDirectory?.trimmedNilIfEmpty
            var environment = [
                "KWWK_LAUNCHER_QUERY": query,
                "KWWK_LAUNCHER_CWD": resolvedWorkingDirectory ?? "",
                "KWWK_LAUNCHER_PREVIOUS_OUTPUT": previousOutput,
            ]
            if let workspace = context.workingDirectory?.trimmedNilIfEmpty ?? resolvedWorkingDirectory {
                environment["KWWK_LAUNCHER_WORKSPACE"] = workspace
            }
            return KWWKCLIInvocation(
                executable: "/bin/zsh",
                arguments: ["-lc", renderedTemplate],
                workingDirectory: resolvedWorkingDirectory,
                environment: environment
            )
        }
    }

    public static func stepOutput(_ result: KWWKCLIRunResult) -> String {
        [result.stdout, result.stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case subtitle
        case systemImage
        case icon
        case keywords
        case model
        case thinking
        case context1m
        case context1M
        case steps
    }

    private static func render(template: String, values: [String: String]) -> String {
        var rendered = ""
        var cursor = template.startIndex

        while let open = template[cursor...].firstIndex(of: "{") {
            rendered += template[cursor..<open]
            guard let close = template[open...].firstIndex(of: "}") else {
                rendered += template[open...]
                return rendered
            }

            let tokenStart = template.index(after: open)
            let token = String(template[tokenStart..<close])
            if token.hasSuffix(":q") {
                let key = String(token.dropLast(2))
                if let value = values[key] {
                    rendered += KWWKShellCommand.quote(value)
                } else {
                    rendered += template[open...close]
                }
            } else if let value = values[token] {
                rendered += value
            } else {
                rendered += template[open...close]
            }

            cursor = template.index(after: close)
        }

        rendered += template[cursor...]
        return rendered
    }
}

public enum LauncherWorkflowIndex {
    public static func defaultURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appendingPathComponent(".kwwk", isDirectory: true)
            .appendingPathComponent("launcher", isDirectory: true)
            .appendingPathComponent("workflows.json")
    }

    public static func load(from url: URL = defaultURL(), limit: Int = 200) -> [LauncherWorkflow] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        let decoded = (try? decoder.decode([LauncherWorkflow].self, from: data))
            ?? (try? decoder.decode(LauncherWorkflowDocument.self, from: data))?.workflows
            ?? []

        var seen = Set<String>()
        return decoded
            .filter { !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .filter { !$0.steps.isEmpty }
            .map { workflow in
                var copy = workflow
                copy.steps = workflow.steps.filter {
                    !$0.template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                return copy
            }
            .filter { !$0.steps.isEmpty }
            .filter { seen.insert($0.id).inserted }
            .sorted { lhs, rhs in
                lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            .prefix(max(0, limit))
            .map { $0 }
    }

    public static func workflow(fromPrompt prompt: String) -> LauncherWorkflow? {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let words = promptWords(trimmed)
        let slug = slug(for: words.isEmpty ? trimmed : words.joined(separator: "-"))

        return LauncherWorkflow(
            id: "saved-\(slug)",
            title: title(for: words.isEmpty ? [trimmed] : words),
            subtitle: "Saved prompt workflow",
            systemImage: "sparkles",
            keywords: keywordSet(values: ["workflow", "ai", "prompt", "saved"] + words),
            steps: [
                LauncherWorkflowStep(
                    id: "ask-kwwk",
                    title: "Ask KWWK",
                    kind: .prompt,
                    template: trimmed
                ),
            ]
        )
    }

    public static func workflow(from record: LauncherCLIContextRecord) -> LauncherWorkflow {
        LauncherWorkflow(
            id: "cli-context-\(record.id)",
            title: "Ask About \(record.title)",
            subtitle: "Saved terminal context workflow",
            systemImage: "terminal",
            keywords: keywordSet(values: [
                "workflow",
                "automation",
                "ai",
                "prompt",
                "saved",
                "terminal context",
                "cli context",
                "captured output",
                "stdin",
                record.id,
                record.title,
                record.path,
                record.displayPath,
            ]),
            steps: [
                LauncherWorkflowStep(
                    id: "ask-kwwk",
                    title: "Ask KWWK",
                    kind: .prompt,
                    template: record.askPrompt
                ),
            ]
        )
    }

    public static func workflow(from record: AIRunHistoryRecord) -> LauncherWorkflow {
        LauncherWorkflow(
            id: "history-\(record.id)",
            title: record.displayTitle,
            subtitle: "Saved from AI history workflow",
            systemImage: "sparkles",
            keywords: keywordSet(values: [
                "workflow",
                "automation",
                "ai",
                "history",
                "saved",
                "prompt",
                record.model ?? "",
            ]),
            steps: [
                LauncherWorkflowStep(
                    id: "ask-kwwk",
                    title: "Ask KWWK",
                    kind: .prompt,
                    template: record.prompt
                ),
            ]
        )
    }

    public static func workflow(fromShellCommand commandText: String) -> LauncherWorkflow? {
        let trimmed = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let words = shellCommandWords(trimmed)
        let slug = slug(for: words.isEmpty ? trimmed : words.joined(separator: "-"))

        return LauncherWorkflow(
            id: "saved-\(slug)",
            title: title(for: words.isEmpty ? [trimmed] : words),
            subtitle: "Saved shell workflow",
            systemImage: "terminal",
            keywords: keywordSet(values: ["workflow", "shell", "command", "saved"] + words),
            steps: [
                LauncherWorkflowStep(
                    id: "run-shell",
                    title: "Run Shell",
                    kind: .shell,
                    template: trimmed
                ),
            ]
        )
    }

    @discardableResult
    public static func upsert(
        _ workflow: LauncherWorkflow,
        to url: URL = defaultURL()
    ) throws -> [LauncherWorkflow] {
        var workflows = load(from: url, limit: Int.max)
        workflows.removeAll { $0.id == workflow.id }
        workflows.append(workflow)
        try save(workflows, to: url)
        return load(from: url, limit: Int.max)
    }

    public static func save(_ workflows: [LauncherWorkflow], to url: URL = defaultURL()) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let sorted = workflows.sorted {
            if $0.title != $1.title {
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            return $0.id.localizedStandardCompare($1.id) == .orderedAscending
        }
        try encoder.encode(sorted).write(to: url, options: .atomic)
    }

    public static func commands(for workflows: [LauncherWorkflow]) -> [LauncherCommand] {
        workflows.map { workflow in
            LauncherCommand(
                id: "workflow:\(workflow.id)",
                title: workflow.title,
                subtitle: workflow.subtitle.isEmpty ? "\(workflow.steps.count) steps" : workflow.subtitle,
                systemImage: workflow.systemImage,
                category: .workflow,
                keywords: keywordSet(values: [
                    workflow.id,
                    workflow.title,
                    workflow.subtitle,
                    "workflow",
                    "automation",
                    "multi step",
                    "ai workflow",
                ] + workflow.keywords),
                action: .runWorkflow(workflow)
            )
        }
    }

    private static func keywordSet(values: [String]) -> [String] {
        var seen = Set<String>()
        return values
            .flatMap { value -> [String] in
                if value.contains(",") {
                    return value.split(separator: ",").map(String.init)
                }
                return [value]
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }

    private static func promptWords(_ prompt: String) -> [String] {
        prompt
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func shellCommandWords(_ commandText: String) -> [String] {
        commandText
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { word in
                let lowercased = word.lowercased()
                return !["bin", "usr", "env", "zsh", "bash", "sh"].contains(lowercased)
            }
    }

    private static func title(for words: [String]) -> String {
        let title = words.prefix(4)
            .map { $0.prefix(1).uppercased() + String($0.dropFirst()) }
            .joined(separator: " ")
        return title.isEmpty ? "Saved Workflow" : title
    }

    private static func slug(for value: String) -> String {
        let scalars = value.lowercased().unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            return "-"
        }
        let collapsed = String(scalars)
            .split(separator: "-")
            .prefix(8)
            .joined(separator: "-")
        return collapsed.isEmpty ? "workflow" : collapsed
    }
}

private struct LauncherWorkflowDocument: Codable {
    var workflows: [LauncherWorkflow]
}

public struct LauncherWorkflowExportRecord: Codable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var systemImage: String
    public var keywords: [String]
    public var stepCount: Int
    public var runtime: String
    public var model: String?
    public var thinking: KWWKThinkingLevel?
    public var context1m: Bool?
    public var cliCommand: String

    public init(workflow: LauncherWorkflow, query: String = "") {
        id = workflow.id
        title = workflow.title
        subtitle = workflow.subtitle
        systemImage = workflow.systemImage
        keywords = workflow.keywords
        stepCount = workflow.steps.count
        runtime = workflow.runtimeDescription
        model = workflow.model
        thinking = workflow.thinking
        context1m = workflow.context1m
        cliCommand = workflow.cliCommand(query: query)
    }
}

public enum LauncherWorkflowExport {
    public static func records(
        for workflows: [LauncherWorkflow],
        query: String = ""
    ) -> [LauncherWorkflowExportRecord] {
        workflows
            .map { LauncherWorkflowExportRecord(workflow: $0, query: query) }
            .sorted { lhs, rhs in
                if lhs.title != rhs.title {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
            }
    }

    public static func table(for workflows: [LauncherWorkflow]) -> String {
        let rows = records(for: workflows)
        guard !rows.isEmpty else { return "" }
        return rows
            .map { "\($0.id)\t\($0.title)\t\($0.stepCount)\t\($0.runtime)" }
            .joined(separator: "\n")
    }

    public static func json(
        for workflows: [LauncherWorkflow],
        query: String = ""
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(records(for: workflows, query: query))
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
