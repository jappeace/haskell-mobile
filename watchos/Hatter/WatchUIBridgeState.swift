import SwiftUI
import os.log

private let bridgeLog = OSLog(subsystem: "me.jappie.hatter", category: "UIBridge")

/// Singleton holding the node pool and root node for SwiftUI rendering.
/// Haskell calls clear/createNode/setStrProp/setRoot etc. via C callbacks.
/// Only setRoot publishes the change to trigger SwiftUI re-render.
class WatchUIBridgeState: ObservableObject {
    static let shared = WatchUIBridgeState()

    @Published var rootNode: WatchUINode?
    var nodes: [Int32: WatchUINode] = [:]
    var nextNodeId: Int32 = 1
    /// IDs available for reuse (from previous render passes).
    var freeIds: [Int32] = []
    /// IDs freed during the current render pass (flushed to freeIds in setRoot).
    var pendingFreeIds: [Int32] = []

    private init() {}

    func createNode(nodeType: Int32) -> Int32 {
        let nodeId: Int32
        if let reused = freeIds.popLast() {
            nodeId = reused
        } else {
            nodeId = nextNodeId
            nextNodeId += 1
        }
        let node = WatchUINode(id: nodeId, nodeType: nodeType)
        nodes[nodeId] = node
        os_log("createNode(type=%d) -> %d", log: bridgeLog, type: .info, nodeType, nodeId)
        return nodeId
    }

    func setStrProp(nodeId: Int32, propId: Int32, value: String) {
        guard let node = nodes[nodeId] else { return }
        switch propId {
        case 0: // UI_PROP_TEXT
            os_log("setStrProp(node=%d, text=\"%{public}s\")", log: bridgeLog, type: .info, nodeId, value)
            node.text = value
        case 1: // UI_PROP_COLOR
            os_log("setStrProp(node=%d, color=\"%{public}s\")", log: bridgeLog, type: .info, nodeId, value)
            node.textColor = value
        case 2: // UI_PROP_HINT
            os_log("setStrProp(node=%d, hint=\"%{public}s\")", log: bridgeLog, type: .info, nodeId, value)
            node.hint = value
        case 3: // UI_PROP_BG_COLOR
            os_log("setStrProp(node=%d, bgColor=\"%{public}s\")", log: bridgeLog, type: .info, nodeId, value)
            node.backgroundColor = value
        case 4: // UI_PROP_IMAGE_RESOURCE
            os_log("setStrProp(node=%d, imageResource=\"%{public}s\")", log: bridgeLog, type: .info, nodeId, value)
            node.imageResource = value
        case 5: // UI_PROP_IMAGE_FILE
            os_log("setStrProp(node=%d, imageFile=\"%{public}s\")", log: bridgeLog, type: .info, nodeId, value)
            node.imageFile = value
        case 6: // UI_PROP_WEBVIEW_URL
            os_log("setStrProp(node=%d, webviewUrl=\"%{public}s\")", log: bridgeLog, type: .info, nodeId, value)
            node.text = value
        default:
            os_log("setStrProp: unknown propId %d", log: bridgeLog, type: .info, propId)
        }
    }

    func setNumProp(nodeId: Int32, propId: Int32, value: Double) {
        guard let node = nodes[nodeId] else { return }
        switch propId {
        case 0: // UI_PROP_FONT_SIZE
            os_log("setNumProp(node=%d, fontSize=%.1f)", log: bridgeLog, type: .info, nodeId, value)
            node.fontSize = CGFloat(value)
        case 1: // UI_PROP_PADDING
            os_log("setNumProp(node=%d, padding=%.1f)", log: bridgeLog, type: .info, nodeId, value)
            node.padding = CGFloat(value)
        case 2: // UI_PROP_INPUT_TYPE
            os_log("setNumProp(node=%d, inputType=%.0f)", log: bridgeLog, type: .info, nodeId, value)
            node.inputType = Int32(value)
        case 4: // UI_PROP_SCALE_TYPE
            os_log("setNumProp(node=%d, scaleType=%.0f)", log: bridgeLog, type: .info, nodeId, value)
            node.scaleType = Int32(value)
        case 5: // UI_PROP_MAP_LAT
            os_log("setNumProp(node=%d, mapLat=%.6f)", log: bridgeLog, type: .info, nodeId, value)
            node.mapLatitude = value
        case 6: // UI_PROP_MAP_LON
            os_log("setNumProp(node=%d, mapLon=%.6f)", log: bridgeLog, type: .info, nodeId, value)
            node.mapLongitude = value
        case 7: // UI_PROP_MAP_ZOOM
            os_log("setNumProp(node=%d, mapZoom=%.1f)", log: bridgeLog, type: .info, nodeId, value)
            node.mapZoom = value
        case 8: // UI_PROP_MAP_SHOW_USER_LOC (no-op on watchOS)
            os_log("setNumProp(node=%d, showUserLoc=%.0f)", log: bridgeLog, type: .info, nodeId, value)
        case 9: // UI_PROP_TRANSLATE_X
            os_log("setNumProp(node=%d, translateX=%.1f)", log: bridgeLog, type: .info, nodeId, value)
            node.translateX = CGFloat(value)
        case 10: // UI_PROP_TRANSLATE_Y
            os_log("setNumProp(node=%d, translateY=%.1f)", log: bridgeLog, type: .info, nodeId, value)
            node.translateY = CGFloat(value)
        case 11: // UI_PROP_AUTO_FOCUS (no-op on watchOS — no keyboard focus)
            os_log("setNumProp(node=%d, autoFocus=%.0f) — no-op on watchOS", log: bridgeLog, type: .info, nodeId, value)
        case 12: // UI_PROP_TOUCH_PASSTHROUGH (no-op on watchOS — ZStack hit testing is automatic)
            os_log("setNumProp(node=%d, touchPassthrough=%.0f) — no-op on watchOS", log: bridgeLog, type: .info, nodeId, value)
        default:
            os_log("setNumProp: unknown propId %d", log: bridgeLog, type: .info, propId)
        }
    }

    func setHandler(nodeId: Int32, eventType: Int32, callbackId: Int32) {
        guard let node = nodes[nodeId] else { return }
        node.callbackId = callbackId
        os_log("setHandler(node=%d, click, callback=%d)", log: bridgeLog, type: .info, nodeId, callbackId)
    }

    func addChild(parentId: Int32, childId: Int32) {
        guard let parent = nodes[parentId], let child = nodes[childId] else { return }
        parent.children.append(child)
    }

    func removeChild(parentId: Int32, childId: Int32) {
        guard let parent = nodes[parentId] else { return }
        parent.children.removeAll { $0.id == childId }
    }

    func destroyNode(nodeId: Int32) {
        nodes.removeValue(forKey: nodeId)
        pendingFreeIds.append(nodeId)
    }

    func setRoot(nodeId: Int32) {
        rootNode = nodes[nodeId]
        // Flush pending freed IDs into the free list now that the render
        // pass is complete.  Prevents same-pass ID reuse.
        freeIds.append(contentsOf: pendingFreeIds)
        pendingFreeIds.removeAll()
        os_log("setRoot(node=%d)", log: bridgeLog, type: .info, nodeId)
    }

    func setImageData(nodeId: Int32, data: UnsafePointer<UInt8>?, length: Int32) {
        guard let node = nodes[nodeId], let data = data else { return }
        node.imageData = Data(bytes: data, count: Int(length))
        os_log("setImageData(node=%d, %d bytes)", log: bridgeLog, type: .info, nodeId, length)
    }

    func clear() {
        rootNode = nil
        nodes.removeAll()
        nextNodeId = 1
        freeIds.removeAll()
        pendingFreeIds.removeAll()
        os_log("clear()", log: bridgeLog, type: .info)
    }
}

// MARK: - C-callable bridge functions (@_cdecl)

@_cdecl("watchos_create_node")
func watchos_create_node(_ nodeType: Int32) -> Int32 {
    return WatchUIBridgeState.shared.createNode(nodeType: nodeType)
}

@_cdecl("watchos_set_str_prop")
func watchos_set_str_prop(_ nodeId: Int32, _ propId: Int32, _ value: UnsafePointer<CChar>?) {
    let str = value.map { String(cString: $0) } ?? ""
    WatchUIBridgeState.shared.setStrProp(nodeId: nodeId, propId: propId, value: str)
}

@_cdecl("watchos_set_num_prop")
func watchos_set_num_prop(_ nodeId: Int32, _ propId: Int32, _ value: Double) {
    WatchUIBridgeState.shared.setNumProp(nodeId: nodeId, propId: propId, value: value)
}

@_cdecl("watchos_set_handler")
func watchos_set_handler(_ nodeId: Int32, _ eventType: Int32, _ callbackId: Int32) {
    WatchUIBridgeState.shared.setHandler(nodeId: nodeId, eventType: eventType, callbackId: callbackId)
}

@_cdecl("watchos_add_child")
func watchos_add_child(_ parentId: Int32, _ childId: Int32) {
    WatchUIBridgeState.shared.addChild(parentId: parentId, childId: childId)
}

@_cdecl("watchos_remove_child")
func watchos_remove_child(_ parentId: Int32, _ childId: Int32) {
    WatchUIBridgeState.shared.removeChild(parentId: parentId, childId: childId)
}

@_cdecl("watchos_destroy_node")
func watchos_destroy_node(_ nodeId: Int32) {
    WatchUIBridgeState.shared.destroyNode(nodeId: nodeId)
}

@_cdecl("watchos_set_root")
func watchos_set_root(_ nodeId: Int32) {
    WatchUIBridgeState.shared.setRoot(nodeId: nodeId)
}

@_cdecl("watchos_set_image_data")
func watchos_set_image_data(_ nodeId: Int32, _ data: UnsafePointer<UInt8>?, _ length: Int32) {
    WatchUIBridgeState.shared.setImageData(nodeId: nodeId, data: data, length: length)
}

@_cdecl("watchos_clear")
func watchos_clear() {
    WatchUIBridgeState.shared.clear()
}
