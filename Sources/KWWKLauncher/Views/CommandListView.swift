#if os(macOS) && canImport(SwiftUI)
import KWWKLauncherCore
import SwiftUI

struct CommandListView: View {
    @ObservedObject var viewModel: LauncherViewModel

    var body: some View {
        Group {
            if viewModel.filteredCommandSections.isEmpty {
                ContentUnavailableView("No Results", systemImage: "magnifyingglass")
                    .accessibilityIdentifier("launcher.commandList.empty")
            } else {
                List(selection: $viewModel.selectedCommandId) {
                    ForEach(viewModel.filteredCommandSections) { section in
                        Section {
                            ForEach(section.commands) { command in
                                CommandRow(command: command)
                                    .environmentObject(viewModel)
                                    .tag(command.id)
                                    .contextMenu {
                                        ForEach(viewModel.selectedCommandActions(for: command)) { action in
                                            Button {
                                                viewModel.run(action, for: command)
                                            } label: {
                                                Label(action.title, systemImage: action.systemImage)
                                            }
                                        }
                                    }
                            }
                        } header: {
                            CommandSectionHeader(section: section)
                        }
                    }
                }
                .listStyle(.sidebar)
                .accessibilityIdentifier("launcher.commandList")
            }
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 2)
        }
        .onMoveCommand { direction in
            switch direction {
            case .up:
                viewModel.moveSelection(-1)
            case .down:
                viewModel.moveSelection(1)
            default:
                break
            }
        }
    }
}

private struct CommandSectionHeader: View {
    var section: LauncherCommandSection

    var body: some View {
        HStack(spacing: 6) {
            Text(section.title)

            Text(section.count.formatted())
                .foregroundStyle(.tertiary)
        }
        .font(.caption)
        .textCase(.uppercase)
        .lineLimit(1)
    }
}

private struct CommandRow: View {
    @EnvironmentObject private var viewModel: LauncherViewModel
    var command: LauncherCommand

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: command.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(command.title)
                    .lineLimit(1)

                Text(command.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if viewModel.isFavorite(command) {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.vertical, 4)
        .accessibilityLabel("\(command.title), \(command.category.rawValue)")
        .accessibilityIdentifier("launcher.command.\(command.id)")
    }
}
#endif
