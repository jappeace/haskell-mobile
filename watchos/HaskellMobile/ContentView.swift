import SwiftUI

/// Recursive SwiftUI renderer for the Haskell widget tree.
struct NodeView: View {
    @ObservedObject var node: WatchUINode

    var body: some View {
        let content = nodeContent
            .ifLet(node.fontSize) { view, size in
                view.font(.system(size: size))
            }
            .ifLet(node.padding) { view, pad in
                view.padding(pad)
            }
            .ifLet(node.textColor.flatMap { Color(hex: $0) }) { view, color in
                view.foregroundColor(color)
            }
            .ifLet(node.backgroundColor.flatMap { Color(hex: $0) }) { view, color in
                view.background(color)
            }
        return content
    }

    @ViewBuilder
    private var nodeContent: some View {
        switch node.nodeType {
        case 0: // UI_NODE_TEXT
            Text(node.text)
        case 1: // UI_NODE_BUTTON
            Button(node.text) {
                HaskellBridge.onUIEvent(node.callbackId)
            }
        case 2: // UI_NODE_COLUMN
            VStack {
                ForEach(node.children) { child in
                    NodeView(node: child)
                }
            }
        case 3: // UI_NODE_ROW
            HStack {
                ForEach(node.children) { child in
                    NodeView(node: child)
                }
            }
        case 4: // UI_NODE_TEXT_INPUT
            TextInputNodeView(node: node)
        case 5: // UI_NODE_SCROLL_VIEW
            ScrollView {
                VStack {
                    ForEach(node.children) { child in
                        NodeView(node: child)
                    }
                }
            }
        case 6: // UI_NODE_IMAGE
            ImageNodeView(node: node)
        default:
            EmptyView()
        }
    }
}

/// Separate view for text input to manage local editing state.
struct TextInputNodeView: View {
    @ObservedObject var node: WatchUINode
    @State private var editingText: String = ""

    var body: some View {
        TextField(node.hint, text: $editingText, onCommit: {
            HaskellBridge.onUITextChange(node.callbackId, editingText)
        })
        .onAppear {
            editingText = node.text
        }
    }
}

/// SwiftUI renderer for Image nodes.
/// Supports resource name, raw data, and file path sources with configurable scale type.
struct ImageNodeView: View {
    @ObservedObject var node: WatchUINode

    var body: some View {
        if let resourceName = node.imageResource {
            imageWithScaleType(Image(resourceName))
        } else if let data = node.imageData, let uiImage = UIImage(data: data) {
            imageWithScaleType(Image(uiImage: uiImage))
        } else if let filePath = node.imageFile, let uiImage = UIImage(contentsOfFile: filePath) {
            imageWithScaleType(Image(uiImage: uiImage))
        } else {
            Text("Image not found")
                .foregroundColor(.secondary)
                .font(.caption)
        }
    }

    @ViewBuilder
    private func imageWithScaleType(_ image: Image) -> some View {
        switch node.scaleType {
        case 1:
            image.resizable().scaledToFill()
        case 2:
            image
        default:
            image.resizable().scaledToFit()
        }
    }
}

/// ContentView wraps the Haskell-driven node tree.
struct ContentView: View {
    @ObservedObject var state = WatchUIBridgeState.shared

    var body: some View {
        Group {
            if let root = state.rootNode {
                NodeView(node: root)
            } else {
                Text("Loading...")
            }
        }
        .onAppear {
            setup_watchos_ui_bridge(HaskellBridge.getContext())
            HaskellBridge.renderUI()

            // CI auto-test: simulate button tap 3s after the initial render.
            if CommandLine.arguments.contains("--autotest") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    HaskellBridge.onUIEvent(0)
                }
            }

            // CI auto-test: exercise both "+" and "-" buttons.
            if CommandLine.arguments.contains("--autotest-buttons") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    HaskellBridge.onUIEvent(0)  // + -> Counter: 1
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    HaskellBridge.onUIEvent(0)  // + -> Counter: 2
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
                    HaskellBridge.onUIEvent(1)  // - -> Counter: 1
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 9) {
                    HaskellBridge.onUIEvent(1)  // - -> Counter: 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 11) {
                    HaskellBridge.onUIEvent(1)  // - -> Counter: -1
                }
            }
        }
    }
}

/// Conditional modifier helper.
extension View {
    @ViewBuilder
    func ifLet<T, Content: View>(_ value: T?, transform: (Self, T) -> Content) -> some View {
        if let value = value {
            transform(self, value)
        } else {
            self
        }
    }
}

/// Parse hex color strings (#RGB, #RRGGBB, or #AARRGGBB) into SwiftUI Color.
extension Color {
    init?(hex: String) {
        guard hex.hasPrefix("#") else { return nil }
        let digits = String(hex.dropFirst())
        guard let raw = UInt64(digits, radix: 16) else { return nil }

        let red: Double
        let green: Double
        let blue: Double
        let opacity: Double

        switch digits.count {
        case 3:
            let r = Double((raw >> 8) & 0xF) * 0x11
            let g = Double((raw >> 4) & 0xF) * 0x11
            let b = Double(raw & 0xF) * 0x11
            red = r / 255.0; green = g / 255.0; blue = b / 255.0; opacity = 1.0
        case 6:
            red = Double((raw >> 16) & 0xFF) / 255.0
            green = Double((raw >> 8) & 0xFF) / 255.0
            blue = Double(raw & 0xFF) / 255.0
            opacity = 1.0
        case 8:
            opacity = Double((raw >> 24) & 0xFF) / 255.0
            red = Double((raw >> 16) & 0xFF) / 255.0
            green = Double((raw >> 8) & 0xFF) / 255.0
            blue = Double(raw & 0xFF) / 255.0
        default:
            return nil
        }
        self.init(red: red, green: green, blue: blue, opacity: opacity)
    }
}
