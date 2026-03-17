import Foundation

/// Swift wrapper around the Haskell FFI functions exposed via C.
class HaskellBridge {
    /// Initialize the Haskell RTS. Must be called before any other Haskell function.
    static func initialize() {
        hs_init(nil, nil)
        haskellInit()
    }

    /// Call Haskell's haskellGreet and return the result as a Swift String.
    /// The C-allocated string is freed after copying.
    static func greet(_ name: String) -> String {
        let result = haskellGreet(name)!
        let greeting = String(cString: result)
        free(result)
        return greeting
    }
}
