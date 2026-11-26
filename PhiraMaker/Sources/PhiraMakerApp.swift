import SwiftUI

@main
struct PhiraMakerApp: App {
    @StateObject private var store = ProjectStore()

    var body: some Scene {
        WindowGroup {
            ProjectListView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}
