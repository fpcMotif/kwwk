#if os(macOS) && canImport(SwiftUI)
import KWWKLauncherCore
import SwiftUI

struct ActionPanelView: View {
    @ObservedObject var viewModel: LauncherViewModel
    @FocusState private var actionSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            Group {
                if viewModel.selectedCommandActions.isEmpty {
                    ContentUnavailableView("No Actions", systemImage: "command")
                        .accessibilityIdentifier("launcher.actionPanel.empty")
                } else {
                    List(selection: $viewModel.selectedActionId) {
                        ForEach(viewModel.selectedCommandActions) { action in
                            ActionRow(action: action)
                                .tag(action.id)
                                .contextMenu {
                                    Button("Run") {
                                        if let command = viewModel.selectedCommand {
                                            viewModel.run(action, for: command)
                                        }
                                    }
                                }
                        }
                    }
                    .listStyle(.inset)
                    .accessibilityIdentifier("launcher.actionPanel.list")
                }
            }
            .onMoveCommand { direction in
                switch direction {
                case .up:
                    viewModel.moveActionSelection(-1)
                case .down:
                    viewModel.moveActionSelection(1)
                default:
                    break
                }
            }

            Divider()

            HStack {
                Button("Cancel") {
                    viewModel.isActionPanelPresented = false
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("launcher.actionPanel.cancel")

                Spacer()

                Button("Run") {
                    viewModel.runSelectedAction()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.selectedAction == nil)
                .accessibilityIdentifier("launcher.actionPanel.run")
            }
            .padding(12)
            .background(.bar)
        }
        .frame(width: 440, height: 360)
        .onAppear {
            viewModel.normalizeActionSelection()
            actionSearchFocused = true
        }
        .onChange(of: viewModel.actionQuery) {
            viewModel.actionQueryDidChange()
        }
        .onExitCommand {
            viewModel.isActionPanelPresented = false
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: viewModel.selectedCommand?.systemImage ?? "command")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.selectedCommand?.title ?? "Actions")
                        .font(.headline)
                        .lineLimit(1)

                    Text("Actions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(14)

            TextField("Search actions", text: $viewModel.actionQuery)
                .textFieldStyle(.roundedBorder)
                .focused($actionSearchFocused)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
                .accessibilityIdentifier("launcher.actionPanel.searchField")
        }
    }
}

private struct ActionRow: View {
    var action: LauncherActionItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: action.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .lineLimit(1)

                Text(action.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
        .padding(.vertical, 4)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityIdentifier("launcher.action.\(action.id)")
    }

    private var accessibilityLabel: String {
        "\(action.title), \(String(describing: action.kind))"
    }
}
#endif
