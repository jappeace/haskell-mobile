import Foundation

/// Swift wrapper around the Haskell FFI functions exposed via C.
class HaskellBridge {
    // Lifecycle event codes (must match HaskellMobile.h)
    static let lifecycleCreate: Int32     = 0
    static let lifecycleStart: Int32      = 1
    static let lifecycleResume: Int32     = 2
    static let lifecyclePause: Int32      = 3
    static let lifecycleStop: Int32       = 4
    static let lifecycleDestroy: Int32    = 5
    static let lifecycleLowMemory: Int32  = 6

    /// Opaque Haskell context pointer, created during initialization.
    private static var context: UnsafeMutableRawPointer?

    /// Initialize the Haskell RTS. Must be called before any other Haskell function.
    static func initialize() {
        hs_init(nil, nil)
        haskellInit()
        context = haskellCreateContext()
    }

    /// Call Haskell's haskellGreet and return the result as a Swift String.
    /// The C-allocated string is freed after copying.
    static func greet(_ name: String) -> String {
        let result = haskellGreet(name)!
        let greeting = String(cString: result)
        free(result)
        return greeting
    }

    /// Notify Haskell of a lifecycle event.
    static func onLifecycle(_ event: Int32) {
        haskellOnLifecycle(context, event)
    }
}
