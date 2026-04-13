import SwiftUI

@main
struct HatterApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        HaskellBridge.initialize()
        HaskellBridge.onLifecycle(HaskellBridge.lifecycleCreate)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active:
                HaskellBridge.onLifecycle(HaskellBridge.lifecycleResume)
            case .inactive:
                HaskellBridge.onLifecycle(HaskellBridge.lifecyclePause)
            case .background:
                HaskellBridge.onLifecycle(HaskellBridge.lifecycleStop)
            @unknown default:
                break
            }
        }
    }
}
