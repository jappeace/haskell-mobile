import Foundation
import os.log

/// watchOS dialog bridge -- uses SwiftUI .alert() via notification center.
/// Provides @_cdecl wrappers callable from C for the platform-agnostic dispatcher.

private let bridgeLog = OSLog(subsystem: "me.jappie.hatter", category: "DialogBridge")

/// Notification posted when a dialog should be shown.
/// userInfo keys: "requestId", "title", "message", "button1", "button2", "button3", "ctx"
let dialogShowNotificationName = Notification.Name("HatterShowDialog")

/// Holds pending dialog info for SwiftUI to observe.
class DialogManager: ObservableObject {
    static let shared = DialogManager()

    @Published var isPresented: Bool = false
    @Published var title: String = ""
    @Published var message: String = ""
    @Published var button1: String = ""
    @Published var button2: String? = nil
    @Published var button3: String? = nil

    var requestId: Int32 = 0
    var ctx: UnsafeMutableRawPointer? = nil

    func show(ctx: UnsafeMutableRawPointer?, requestId: Int32,
              title: String, message: String,
              button1: String, button2: String?, button3: String?) {
        self.ctx = ctx
        self.requestId = requestId
        self.title = title
        self.message = message
        self.button1 = button1
        self.button2 = button2
        self.button3 = button3
        self.isPresented = true
    }

    func onButton(_ actionCode: Int32) {
        isPresented = false
        haskellOnDialogResult(ctx, requestId, actionCode)
    }
}

@_cdecl("watchos_dialog_show")
func watchosDialogShow(_ ctx: UnsafeMutableRawPointer?,
                        _ requestId: Int32,
                        _ title: UnsafePointer<CChar>?,
                        _ message: UnsafePointer<CChar>?,
                        _ button1: UnsafePointer<CChar>?,
                        _ button2: UnsafePointer<CChar>?,
                        _ button3: UnsafePointer<CChar>?) {
    guard let title = title, let message = message, let button1 = button1 else {
        haskellOnDialogResult(ctx, requestId, 3 /* DISMISSED */)
        return
    }

    let titleStr = String(cString: title)
    let messageStr = String(cString: message)
    let button1Str = String(cString: button1)
    let button2Str: String? = button2.map { String(cString: $0) }
    let button3Str: String? = button3.map { String(cString: $0) }

    os_log("dialog_show(title=%{public}s, id=%d)", log: bridgeLog, type: .info, titleStr, requestId)

    // In autotest mode, auto-press button 1 without presenting the dialog.
    // The autotest mechanism only fires widget button callbacks (onUIEvent),
    // it cannot tap native SwiftUI .alert() buttons.
    let args = CommandLine.arguments
    if args.contains("--autotest-buttons") || args.contains("--autotest") {
        os_log("dialog_show: autotest mode — auto-pressing button 1", log: bridgeLog, type: .info)
        haskellOnDialogResult(ctx, requestId, DIALOG_BUTTON_1)
        return
    }

    DispatchQueue.main.async {
        DialogManager.shared.show(ctx: ctx, requestId: requestId,
                                  title: titleStr, message: messageStr,
                                  button1: button1Str, button2: button2Str,
                                  button3: button3Str)
    }
}
