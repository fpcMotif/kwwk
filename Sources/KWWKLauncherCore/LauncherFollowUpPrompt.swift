import Foundation

public enum LauncherFollowUpPromptBuilder {
    public static func prompt(
        request: String,
        previousOutput: String,
        sourceTitle: String? = nil
    ) -> String {
        let trimmedRequest = request.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOutput = previousOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = [
            "Use the previous launcher result as context and answer the follow-up request.",
            "Keep the answer concrete, concise, and CLI-friendly when commands are useful.",
        ]

        if let sourceTitle = sourceTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sourceTitle.isEmpty {
            lines.append(contentsOf: ["", "Previous result source:", sourceTitle])
        }

        lines.append(contentsOf: [
            "",
            "Follow-up request:",
            trimmedRequest,
            "",
            "Previous launcher result:",
            trimmedOutput,
        ])

        return lines.joined(separator: "\n")
    }
}

public enum LauncherResultDraftPromptBuilder {
    public static func prompt(
        output: String,
        sourceTitle: String? = nil,
        maxOutputLength: Int = 12_000
    ) -> String? {
        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOutput.isEmpty else { return nil }

        var lines = [
            "Use this launcher result as context for an interactive CLI session.",
            "Continue from the result, preserve important details, and propose concrete next actions.",
        ]

        if let sourceTitle = sourceTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sourceTitle.isEmpty {
            lines.append(contentsOf: ["", "Launcher result source:", sourceTitle])
        }

        lines.append(contentsOf: [
            "",
            "Launcher result:",
            bounded(trimmedOutput, maxLength: maxOutputLength),
        ])

        return lines.joined(separator: "\n")
    }

    private static func bounded(_ value: String, maxLength: Int) -> String {
        guard value.count > maxLength else { return value }
        let end = value.index(value.startIndex, offsetBy: maxLength)
        return String(value[..<end]) + "\n\n[truncated]"
    }
}
