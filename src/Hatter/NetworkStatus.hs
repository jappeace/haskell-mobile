{-# LANGUAGE ForeignFunctionInterface #-}
-- | Network connectivity status API for mobile platforms.
--
-- Provides start\/stop network monitoring with connected status and
-- transport type (wifi, cellular, ethernet) delivered via a streaming
-- callback.  Only one network listener is active at a time (same
-- single-listener pattern as Location\/BLE).
--
-- On desktop (no platform bridge registered) the C stub dispatches
-- a fixed status (connected=1, transport=wifi) on
-- 'startNetworkMonitoring', so @cabal test@ works without native code.
module Hatter.NetworkStatus
  ( NetworkTransport(..)
  , NetworkStatus(..)
  , NetworkStatusState(..)
  , newNetworkStatusState
  , startNetworkMonitoring
  , stopNetworkMonitoring
  , dispatchNetworkStatusChange
  , networkTransportFromInt
  , networkTransportToInt
  )
where

import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Foreign.C.Types (CInt(..))
import Foreign.Ptr (Ptr, nullPtr)

-- | Transport type of the active network connection.
data NetworkTransport
  = TransportNone
  | TransportWifi
  | TransportCellular
  | TransportEthernet
  | TransportOther
  deriving (Show, Eq, Ord, Enum, Bounded)

-- | Current network connectivity status.
data NetworkStatus = NetworkStatus
  { nsConnected :: Bool
  , nsTransport :: NetworkTransport
  } deriving (Show, Eq)

-- | Mutable state for the network status subsystem.
-- Uses 'IORef (Maybe callback)' because only one network listener
-- can be active at a time.
data NetworkStatusState = NetworkStatusState
  { nssUpdateCallback :: IORef (Maybe (NetworkStatus -> IO ()))
    -- ^ Active network status callback, or 'Nothing' if not listening.
  , nssContextPtr     :: IORef (Ptr ())
    -- ^ Opaque context pointer passed to the C bridge.
    -- Set by 'AppContext.newAppContext' after the 'StablePtr' is created.
  }

-- | Create a fresh 'NetworkStatusState' with no active listener.
-- The context pointer is initially null and must be set via
-- 'nssContextPtr' before calling 'startNetworkMonitoring'.
newNetworkStatusState :: IO NetworkStatusState
newNetworkStatusState = do
  updateCallback <- newIORef Nothing
  contextPtr     <- newIORef nullPtr
  pure NetworkStatusState
    { nssUpdateCallback = updateCallback
    , nssContextPtr     = contextPtr
    }

-- | Start receiving network status updates. Stops any existing listener
-- first, then registers the callback and calls the C bridge. The callback
-- will be invoked for each connectivity change until
-- 'stopNetworkMonitoring' is called.
startNetworkMonitoring :: NetworkStatusState -> (NetworkStatus -> IO ()) -> IO ()
startNetworkMonitoring networkStatusState callback = do
  -- Stop any existing listener first
  c_networkStatusStopMonitoring
  -- Register the new callback
  writeIORef (nssUpdateCallback networkStatusState) (Just callback)
  -- Start monitoring via C bridge
  ctx <- readIORef (nssContextPtr networkStatusState)
  c_networkStatusStartMonitoring ctx

-- | Stop receiving network status updates. Clears the callback so that
-- any late-arriving updates are silently dropped.
stopNetworkMonitoring :: NetworkStatusState -> IO ()
stopNetworkMonitoring networkStatusState = do
  writeIORef (nssUpdateCallback networkStatusState) Nothing
  c_networkStatusStopMonitoring

-- | Dispatch a network status change from the platform back to the
-- registered Haskell callback. Called from the FFI entry point.
-- If no listener is active (callback is 'Nothing'), the update is
-- silently dropped.
dispatchNetworkStatusChange :: NetworkStatusState -> CInt -> CInt -> IO ()
dispatchNetworkStatusChange networkStatusState cConnected cTransport = do
  maybeCallback <- readIORef (nssUpdateCallback networkStatusState)
  case maybeCallback of
    Nothing -> pure ()  -- No active listener, drop update
    Just callback -> do
      let networkStatus = NetworkStatus
            { nsConnected = cConnected /= 0
            , nsTransport = networkTransportFromInt cTransport
            }
      callback networkStatus

-- | Convert an integer transport code from C to 'NetworkTransport'.
-- Unknown codes map to 'TransportOther'.
networkTransportFromInt :: CInt -> NetworkTransport
networkTransportFromInt 0 = TransportNone
networkTransportFromInt 1 = TransportWifi
networkTransportFromInt 2 = TransportCellular
networkTransportFromInt 3 = TransportEthernet
networkTransportFromInt 4 = TransportOther
networkTransportFromInt _ = TransportOther

-- | Convert a 'NetworkTransport' to its integer code for C.
networkTransportToInt :: NetworkTransport -> CInt
networkTransportToInt TransportNone     = 0
networkTransportToInt TransportWifi     = 1
networkTransportToInt TransportCellular = 2
networkTransportToInt TransportEthernet = 3
networkTransportToInt TransportOther    = 4

-- | FFI import: start network monitoring via the C bridge.
foreign import ccall "network_status_start_monitoring"
  c_networkStatusStartMonitoring :: Ptr () -> IO ()

-- | FFI import: stop network monitoring via the C bridge.
foreign import ccall "network_status_stop_monitoring"
  c_networkStatusStopMonitoring :: IO ()
