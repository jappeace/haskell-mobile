import Foundation
import os.log

/// watchOS bottom sheet bridge -- uses SwiftUI .confirmationDialog() via notification center.
/// Provides @_cdecl wrappers callable from C for the platform-agnostic dispatcher.

private let bridgeLog = OSLog(subsystem: "me.jappie.hatter", category: "BottomSheetBridge")

/// Notification posted when a bottom sheet should be shown.
/// userInfo keys: "requestId", "title", "items", "ctx"
let bottomSheetShowNotificationName = Notification.Name("HatterShowBottomSheet")

/// Holds pending bottom sheet info for SwiftUI to observe.
class BottomSheetManager: ObservableObject {
    static let shared = BottomSheetManager()

    @Published var isPresented: Bool = false
    @Published var title: String = ""
    @Published var items: [String] = []

    var requestId: Int32 = 0
    var ctx: UnsafeMutableRawPointer? = nil

    func show(ctx: UnsafeMutableRawPointer?, requestId: Int32,
              title: String, items: [String]) {
        self.ctx = ctx
        self.requestId = requestId
        self.title = title
        self.items = items
        self.isPresented = true
    }

    func onItemSelected(_ index: Int32) {
        isPresented = false
        haskellOnBottomSheetResult(ctx, requestId, index)
    }

    func onDismissed() {
        isPresented = false
        haskellOnBottomSheetResult(ctx, requestId, BOTTOM_SHEET_DISMISSED)
    }
}

@_cdecl("watchos_bottom_sheet_show")
func watchosBottomSheetShow(_ ctx: UnsafeMutableRawPointer?,
                             _ requestId: Int32,
                             _ title: UnsafePointer<CChar>?,
                             _ items: UnsafePointer<CChar>?) {
    guard let title = title, let items = items else {
        haskellOnBottomSheetResult(ctx, requestId, BOTTOM_SHEET_DISMISSED)
        return
    }

    let titleStr = String(cString: title)
    let itemsStr = String(cString: items)
    let itemLabels = itemsStr.components(separatedBy: "\n")

    os_log("bottom_sheet_show(title=%{public}s, id=%d)", log: bridgeLog, type: .info, titleStr, requestId)

    // In autotest mode, auto-select first item without presenting the sheet.
    let args = CommandLine.arguments
    if args.contains("--autotest-buttons") || args.contains("--autotest") {
        os_log("bottom_sheet_show: autotest mode -- auto-selecting first item", log: bridgeLog, type: .info)
        haskellOnBottomSheetResult(ctx, requestId, 0)
        return
    }

    DispatchQueue.main.async {
        BottomSheetManager.shared.show(ctx: ctx, requestId: requestId,
                                        title: titleStr, items: itemLabels)
    }
}
