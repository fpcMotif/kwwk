import KWWKLauncherCore
import Testing

@Suite("Launcher action filter")
struct LauncherActionFilterTests {
    @Test
    func blankQueryKeepsOriginalActionOrder() {
        let actions = [
            action(id: "primary", title: "Run"),
            action(id: "favorite", title: "Favorite"),
            action(id: "copy", title: "Copy Result"),
        ]

        let results = LauncherActionFilter.filter(actions, query: "   ")

        #expect(results.map(\.id) == ["primary", "favorite", "copy"])
    }

    @Test
    func filtersAndRanksActionsByTitleIdAndSubtitle() {
        let actions = [
            action(id: "primary", title: "Run", subtitle: "Open selected item"),
            action(id: "copy-launcher-command", title: "Copy Launcher Command", subtitle: "kwwk launcher --command open-cli --run"),
            action(id: "copy-path", title: "Copy Path", subtitle: "/Users/f/project"),
        ]

        let copyResults = LauncherActionFilter.filter(actions, query: "copy")
        let launcherResults = LauncherActionFilter.filter(actions, query: "launcher command")

        #expect(copyResults.map(\.id) == ["copy-launcher-command", "copy-path"])
        #expect(launcherResults.map(\.id) == ["copy-launcher-command"])
    }

    private func action(id: String, title: String, subtitle: String = "") -> LauncherActionItem {
        LauncherActionItem(
            id: id,
            title: title,
            subtitle: subtitle,
            systemImage: "command",
            kind: .runPrimary
        )
    }
}
