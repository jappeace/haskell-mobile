import SwiftUI

struct ContentView: View {
    @State private var greeting: String = "Loading..."

    var body: some View {
        VStack(spacing: 20) {
            Text(greeting)
                .font(.title)
                .padding()
        }
        .onAppear {
            greeting = HaskellBridge.greet("iOS")
        }
    }
}
