import SwiftUI

@main
struct SQLiteVaultApp: App {
    @State private var store = VaultStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .task { await store.bootstrap() }
        }
    }
}
