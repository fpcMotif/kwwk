#if os(macOS) && canImport(SwiftUI)
import Foundation
import KWWKLauncherCore
import SwiftUI

@MainActor
final class LauncherMenuModel: ObservableObject {
    @Published var favorites: [LauncherMenuCommand] = []
    @Published var recents: [LauncherMenuCommand] = []
    @Published var terminalContexts: [LauncherMenuCommand] = []

    func reload() {
        Task.detached(priority: .utility) {
            let usage = Self.loadUsage()
            let terminalContexts = LauncherCLIContextIndex.scan(limit: 4)
            let commands = Self.loadCommands(terminalContexts: terminalContexts)
            let sections = LauncherMenuCommandFactory.sections(
                from: commands,
                usage: usage,
                terminalContexts: terminalContexts
            )

            await MainActor.run {
                self.favorites = sections.favorites
                self.recents = sections.recents
                self.terminalContexts = sections.terminalContexts
            }
        }
    }

    nonisolated private static func loadUsage() -> LauncherCommandUsage {
        guard let data = UserDefaults.standard.data(forKey: LauncherCommandUsage.defaultsKey),
              let usage = try? JSONDecoder().decode(LauncherCommandUsage.self, from: data)
        else {
            return LauncherCommandUsage()
        }
        return usage
    }

    nonisolated private static func loadCommands(
        terminalContexts: [LauncherCLIContextRecord]
    ) -> [LauncherCommand] {
        LauncherResidentCommandCatalog.commands(cliContexts: terminalContexts)
    }
}
#endif
