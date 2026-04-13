{-# LANGUAGE ForeignFunctionInterface #-}
-- | Location (GPS) services API for mobile platforms.
--
-- Provides start\/stop location updates with latitude, longitude,
-- altitude, and accuracy delivered via a streaming callback.
-- Only one location listener is active at a time (similar to BLE).
--
-- On desktop (no platform bridge registered) the C stub dispatches
-- a fixed location (Amsterdam: lat=52.37, lon=4.90) on
-- 'startLocationUpdates', so @cabal test@ works without native code.
module Hatter.Location
  ( LocationData(..)
  , LocationState(..)
  , newLocationState
  , startLocationUpdates
  , stopLocationUpdates
  , dispatchLocationUpdate
  )
where

import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Foreign.C.Types (CDouble(..))
import Foreign.Ptr (Ptr, nullPtr)

-- | A single location fix delivered by the platform.
data LocationData = LocationData
  { ldLatitude  :: Double
  , ldLongitude :: Double
  , ldAltitude  :: Double
  , ldAccuracy  :: Double
  } deriving (Show, Eq)

-- | Mutable state for the location subsystem.
-- Uses 'IORef (Maybe callback)' because only one location listener
-- can be active at a time.
data LocationState = LocationState
  { lsUpdateCallback :: IORef (Maybe (LocationData -> IO ()))
    -- ^ Active location update callback, or 'Nothing' if not listening.
  , lsContextPtr     :: IORef (Ptr ())
    -- ^ Opaque context pointer passed to the C bridge.
    -- Set by 'AppContext.newAppContext' after the 'StablePtr' is created.
  }

-- | Create a fresh 'LocationState' with no active listener.
-- The context pointer is initially null and must be set via
-- 'lsContextPtr' before calling 'startLocationUpdates'.
newLocationState :: IO LocationState
newLocationState = do
  updateCallback <- newIORef Nothing
  contextPtr     <- newIORef nullPtr
  pure LocationState
    { lsUpdateCallback = updateCallback
    , lsContextPtr     = contextPtr
    }

-- | Start receiving location updates. Stops any existing listener first,
-- then registers the callback and calls the C bridge. The callback will
-- be invoked for each location fix until 'stopLocationUpdates' is called.
startLocationUpdates :: LocationState -> (LocationData -> IO ()) -> IO ()
startLocationUpdates locationState callback = do
  -- Stop any existing listener first
  c_locationStopUpdates
  -- Register the new callback
  writeIORef (lsUpdateCallback locationState) (Just callback)
  -- Start updates via C bridge
  ctx <- readIORef (lsContextPtr locationState)
  c_locationStartUpdates ctx

-- | Stop receiving location updates. Clears the callback so that any
-- late-arriving fixes are silently dropped.
stopLocationUpdates :: LocationState -> IO ()
stopLocationUpdates locationState = do
  writeIORef (lsUpdateCallback locationState) Nothing
  c_locationStopUpdates

-- | Dispatch a location update from the platform back to the
-- registered Haskell callback. Called from the FFI entry point.
-- If no listener is active (callback is 'Nothing'), the update is
-- silently dropped.
dispatchLocationUpdate :: LocationState -> CDouble -> CDouble -> CDouble -> CDouble -> IO ()
dispatchLocationUpdate locationState cLat cLon cAlt cAcc = do
  maybeCallback <- readIORef (lsUpdateCallback locationState)
  case maybeCallback of
    Nothing -> pure ()  -- No active listener, drop update
    Just callback -> do
      let locationData = LocationData
            { ldLatitude  = realToFrac cLat
            , ldLongitude = realToFrac cLon
            , ldAltitude  = realToFrac cAlt
            , ldAccuracy  = realToFrac cAcc
            }
      callback locationData

-- | FFI import: start location updates via the C bridge.
foreign import ccall "location_start_updates"
  c_locationStartUpdates :: Ptr () -> IO ()

-- | FFI import: stop location updates via the C bridge.
foreign import ccall "location_stop_updates"
  c_locationStopUpdates :: IO ()
