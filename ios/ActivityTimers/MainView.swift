import SwiftUI

/// The signed-in app: a tab bar with the timers, sessions, stats and settings.
struct MainView: View {
    let onSignOut: () -> Void
    @State private var store: TimersStore
    @State private var tab: Tab

    enum Tab: String {
        case timers, sessions, stats, settings
    }

    init(uid: String, onSignOut: @escaping () -> Void) {
        self.onSignOut = onSignOut
        _store = State(initialValue: TimersStore(uid: uid))
        _tab = State(initialValue: DebugLaunch.tab.flatMap(Tab.init) ?? .timers)
    }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { TimersView(store: store) }
                .tabItem { Label("Timers", systemImage: "timer") }
                .tag(Tab.timers)
            NavigationStack { SessionsView(timers: store) }
                .tabItem { Label("Sessions", systemImage: "list.bullet.rectangle") }
                .tag(Tab.sessions)
            NavigationStack { StatsView(timers: store) }
                .tabItem { Label("Stats", systemImage: "chart.xyaxis.line") }
                .tag(Tab.stats)
            NavigationStack { SettingsView(timers: store, onSignOut: onSignOut) }
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .task { await store.run() }
        // Widget / Live Activity taps open activitytimers://timers.
        .onOpenURL { url in
            if url.host == timersScreenURL.host { tab = .timers }
        }
    }
}

/// Launch arguments for opening specific screens in the Simulator, e.g.
/// `-debugTab stats -debugStatsSelectDaysAgo 3`. Ignored in release builds.
enum DebugLaunch {
    private static func string(_ key: String) -> String? {
        #if DEBUG
        UserDefaults.standard.string(forKey: key)
        #else
        nil
        #endif
    }

    static var tab: String? { string("debugTab") }
    static var statsSelectDaysAgo: Int? { string("debugStatsSelectDaysAgo").flatMap { Int($0) } }
    static var sessionsDaysAgo: Int? { string("debugSessionsDaysAgo").flatMap { Int($0) } }
    /// Day keys treated as excluded in the stats chart only (nothing is written).
    static var excludeDays: Set<String> {
        Set((string("debugExcludeDays") ?? "").split(separator: ",").map(String.init))
    }
    /// An activity type id to open in the editor, or "new".
    static var editActivity: String? { string("debugEditActivity") }
    /// A group id to open in the group editor.
    static var editGroup: String? { string("debugEditGroup") }
}
