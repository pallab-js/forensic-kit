import SwiftUI
import ForensicKitDesktopCore

@main
struct ForensicKitDesktopApp: App {
    @State private var state = AppState()

    var body: some Scene {
        Window("ForensicKit Desktop", id: "main") {
            ContentView()
                .environment(state)
                .frame(minWidth: 900, minHeight: 600)
        }
    }
}
