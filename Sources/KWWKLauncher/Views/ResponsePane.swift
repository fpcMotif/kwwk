#if os(macOS) && canImport(SwiftUI)
import SwiftUI

struct ResponsePane: View {
    @ObservedObject var viewModel: LauncherViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
                    .frame(width: 18)

                Text(title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 10)

            ScrollView {
                if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView("No Preview", systemImage: "sparkles")
                        .frame(maxWidth: .infinity, minHeight: 220)
                        .accessibilityIdentifier("launcher.response.empty")
                } else {
                    Text(content)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .accessibilityIdentifier("launcher.response.content")
                }
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.45))
            .accessibilityIdentifier("launcher.response.scrollView")

            Divider()

            VStack(spacing: 0) {
                if !viewModel.selectedCommandFeaturedActions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.selectedCommandFeaturedActions) { action in
                                Button {
                                    if let command = viewModel.selectedCommand {
                                        viewModel.run(action, for: command)
                                    }
                                } label: {
                                    Label(action.title, systemImage: action.systemImage)
                                .lineLimit(1)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .accessibilityIdentifier("launcher.featuredAction.\(action.id)")
                                .help(action.subtitle)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                        .padding(.bottom, 4)
                    }
                }

                HStack(spacing: 10) {
                    if viewModel.canCancelRun {
                        Button {
                            viewModel.cancelRunningCommand()
                        } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .accessibilityIdentifier("launcher.response.stop")
                } else {
                    Button {
                        viewModel.runSelectedCommand()
                    } label: {
                        Label(viewModel.selectedCommandPrimaryActionTitle, systemImage: "return")
                    }
                    .accessibilityIdentifier("launcher.response.primary")
                }

                    Button {
                        viewModel.toggleSelectedFavorite()
                    } label: {
                        Label(
                            viewModel.selectedCommandIsFavorite ? "Unfavorite" : "Favorite",
                            systemImage: viewModel.selectedCommandIsFavorite ? "star.fill" : "star"
                        )
                    }
                    .disabled(viewModel.selectedCommand == nil)
                    .accessibilityIdentifier("launcher.response.favorite")

                    Button {
                        viewModel.showActionPanel()
                    } label: {
                        Label("Actions", systemImage: "command")
                    }
                    .disabled(viewModel.selectedCommand == nil)
                    .keyboardShortcut("k", modifiers: [.command])
                    .accessibilityIdentifier("launcher.response.actions")

                    Button {
                        viewModel.askFollowUp()
                    } label: {
                        Label("Follow Up", systemImage: "sparkles")
                    }
                    .disabled(!viewModel.canAskFollowUp)
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
                    .accessibilityIdentifier("launcher.response.followUp")

                    Button {
                        viewModel.openOutputDraftInCLI()
                    } label: {
                        Label("Open Draft", systemImage: "terminal")
                    }
                    .disabled(!viewModel.canOpenOutputDraft)
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                    .accessibilityIdentifier("launcher.response.openDraft")

                    Button {
                        viewModel.saveOutputAsSnippet()
                    } label: {
                        Label("Save Snippet", systemImage: "text.quote")
                    }
                    .disabled(!viewModel.canSaveOutputAsSnippet)
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .accessibilityIdentifier("launcher.response.saveSnippet")

                    Button {
                        viewModel.copyOutput()
                    } label: {
                        Label("Copy Result", systemImage: "doc.on.doc")
                    }
                    .disabled(!viewModel.canCopyOutput)
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .accessibilityIdentifier("launcher.response.copy")

                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .background(.bar)
        }
    }

    private var title: String {
        switch viewModel.status {
        case .idle, .waitingForPrompt:
            return viewModel.selectedCommand?.title ?? "KWWK"
        case .running:
            return "KWWK"
        case .succeeded(let message), .failed(let message):
            return message
        case .cancelled:
            return "Stopped"
        }
    }

    private var content: String {
        if !viewModel.output.isEmpty {
            return viewModel.output
        }
        return viewModel.selectedCommandPreview
    }

    private var iconName: String {
        switch viewModel.status {
        case .failed:
            return "exclamationmark.triangle"
        case .cancelled:
            return "stop.fill"
        case .running:
            return "bolt.horizontal"
        default:
            return viewModel.selectedCommand?.systemImage ?? "sparkles"
        }
    }

    private var iconColor: Color {
        switch viewModel.status {
        case .failed:
            return .red
        case .cancelled:
            return .orange
        case .running:
            return .blue
        default:
            return .secondary
        }
    }
}
#endif
