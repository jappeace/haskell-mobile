import SwiftUI

@main
struct HaskellMobileApp: App {
    init() {
        HaskellBridge.initialize()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
