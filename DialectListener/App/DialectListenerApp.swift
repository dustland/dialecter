import SwiftUI
import SwiftData

@main
struct DialectListenerApp: App {
    
    // Setup modern SwiftData container for our models
    let container: ModelContainer
    
    init() {
        do {
            // Include Session and Bookmark in the persistent schema
            container = try ModelContainer(for: Session.self, Bookmark.self)
        } catch {
            fatalError("Failed to initialize SwiftData ModelContainer: \(error.localizedDescription)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .preferredColorScheme(.dark) // Forced dark mode for premium street readability
        }
        .modelContainer(container)
    }
}
