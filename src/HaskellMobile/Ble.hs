{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE OverloadedStrings #-}
-- | BLE (Bluetooth Low Energy) scanning API for mobile platforms.
--
-- Provides adapter status check and start\/stop scan functionality.
-- Scan results are delivered via a streaming callback (multiple
-- invocations per scan), unlike the permission bridge which uses
-- one callback per request.
--
-- On desktop (no platform bridge registered) the C stub reports
-- the adapter as on and start\/stop scan are no-ops, so @cabal test@
-- works without native code.
module HaskellMobile.Ble
  ( BleAdapterStatus(..)
  , BleScanResult(..)
  , BleState(..)
  , newBleState
  , bleAdapterStatusFromInt
  , bleAdapterStatusToInt
  , checkBleAdapter
  , startBleScan
  , stopBleScan
  , dispatchBleScanResult
  )
where

import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.Text (Text, pack)
import Foreign.C.String (CString, peekCString)
import Foreign.C.Types (CInt(..))
import Foreign.Ptr (Ptr, nullPtr)
import System.IO (hPutStrLn, stderr)

-- | Status of the platform's BLE adapter.
data BleAdapterStatus
  = BleAdapterOff
  | BleAdapterOn
  | BleAdapterUnauthorized
  | BleAdapterUnsupported
  deriving (Show, Eq, Ord, Enum, Bounded)

-- | A single BLE scan result delivered by the platform.
data BleScanResult = BleScanResult
  { bsrDeviceName    :: Text
  , bsrDeviceAddress :: Text
  , bsrRssi          :: Int
  } deriving (Show, Eq)

-- | Mutable state for the BLE scanning subsystem.
-- Uses 'IORef (Maybe callback)' instead of 'IntMap' because only
-- one scan can be active at a time.
data BleState = BleState
  { blesScanCallback :: IORef (Maybe (BleScanResult -> IO ()))
    -- ^ Active scan result callback, or 'Nothing' if not scanning.
  , blesContextPtr   :: IORef (Ptr ())
    -- ^ Opaque context pointer passed to the C bridge.
    -- Set by 'AppContext.newAppContext' after the 'StablePtr' is created.
  }

-- | Create a fresh 'BleState' with no active scan.
-- The context pointer is initially null and must be set via
-- 'blesContextPtr' before calling 'startBleScan'.
newBleState :: IO BleState
newBleState = do
  scanCallback <- newIORef Nothing
  contextPtr   <- newIORef nullPtr
  pure BleState
    { blesScanCallback = scanCallback
    , blesContextPtr   = contextPtr
    }

-- | Convert a C bridge adapter status code to 'BleAdapterStatus'.
-- Returns 'Nothing' for unknown codes.
bleAdapterStatusFromInt :: CInt -> Maybe BleAdapterStatus
bleAdapterStatusFromInt 0 = Just BleAdapterOff
bleAdapterStatusFromInt 1 = Just BleAdapterOn
bleAdapterStatusFromInt 2 = Just BleAdapterUnauthorized
bleAdapterStatusFromInt 3 = Just BleAdapterUnsupported
bleAdapterStatusFromInt _ = Nothing

-- | Convert a 'BleAdapterStatus' to its C bridge integer code.
-- Must match the @BLE_ADAPTER_*@ constants in @BleBridge.h@.
bleAdapterStatusToInt :: BleAdapterStatus -> CInt
bleAdapterStatusToInt BleAdapterOff          = 0
bleAdapterStatusToInt BleAdapterOn           = 1
bleAdapterStatusToInt BleAdapterUnauthorized = 2
bleAdapterStatusToInt BleAdapterUnsupported  = 3

-- | Check the BLE adapter status (synchronous).
checkBleAdapter :: IO BleAdapterStatus
checkBleAdapter = do
  result <- c_bleCheckAdapter
  case bleAdapterStatusFromInt result of
    Just status -> pure status
    Nothing     -> do
      hPutStrLn stderr $ "checkBleAdapter: unknown status code " ++ show result
      pure BleAdapterUnsupported

-- | Start a BLE scan. Stops any existing scan first, then registers
-- the callback and calls the C bridge. The callback will be invoked
-- for each discovered device until 'stopBleScan' is called.
startBleScan :: BleState -> (BleScanResult -> IO ()) -> IO ()
startBleScan bleState callback = do
  -- Stop any existing scan first
  c_bleStopScan
  -- Register the new callback
  writeIORef (blesScanCallback bleState) (Just callback)
  -- Start scanning via C bridge
  ctx <- readIORef (blesContextPtr bleState)
  c_bleStartScan ctx

-- | Stop a running BLE scan. Clears the callback so that any
-- late-arriving results are silently dropped.
stopBleScan :: BleState -> IO ()
stopBleScan bleState = do
  writeIORef (blesScanCallback bleState) Nothing
  c_bleStopScan

-- | Dispatch a BLE scan result from the platform back to the
-- registered Haskell callback. Called from the FFI entry point.
-- If no scan is active (callback is 'Nothing'), the result is
-- silently dropped.
dispatchBleScanResult :: BleState -> CString -> CString -> CInt -> IO ()
dispatchBleScanResult bleState cName cAddr cRssi = do
  maybeCallback <- readIORef (blesScanCallback bleState)
  case maybeCallback of
    Nothing -> pure ()  -- No active scan, drop result
    Just callback -> do
      nameStr <- if cName == nullPtr
        then pure ""
        else pack <$> peekCString cName
      addrStr <- if cAddr == nullPtr
        then pure ""
        else pack <$> peekCString cAddr
      let scanResult = BleScanResult
            { bsrDeviceName    = nameStr
            , bsrDeviceAddress = addrStr
            , bsrRssi          = fromIntegral cRssi
            }
      callback scanResult

-- | FFI import: check BLE adapter status via the C bridge.
foreign import ccall "ble_check_adapter"
  c_bleCheckAdapter :: IO CInt

-- | FFI import: start BLE scan via the C bridge.
foreign import ccall "ble_start_scan"
  c_bleStartScan :: Ptr () -> IO ()

-- | FFI import: stop BLE scan via the C bridge.
foreign import ccall "ble_stop_scan"
  c_bleStopScan :: IO ()
