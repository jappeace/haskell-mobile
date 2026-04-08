import SwiftUI
import os.log

/// Observable node model for SwiftUI rendering.
/// Each node has a type, properties, children, and an optional callback ID.
class WatchUINode: ObservableObject, Identifiable {
    let id: Int32
    let nodeType: Int32

    @Published var text: String = ""
    @Published var hint: String = ""
    @Published var fontSize: CGFloat?
    @Published var padding: CGFloat?
    @Published var inputType: Int32 = 0
    @Published var callbackId: Int32 = -1
    @Published var textColor: String?
    @Published var backgroundColor: String?
    @Published var children: [WatchUINode] = []

    init(id: Int32, nodeType: Int32) {
        self.id = id
        self.nodeType = nodeType
    }
}
