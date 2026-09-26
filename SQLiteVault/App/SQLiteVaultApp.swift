import SwiftUI

@main
struct SQLiteVaultApp: App {
    @State private var store = VaultStore()
    @State private var preferences = VaultPreferences()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(preferences)
                .environment(\.locale, preferences.language.locale)
                .task { await store.bootstrap() }
        }
    }
}
