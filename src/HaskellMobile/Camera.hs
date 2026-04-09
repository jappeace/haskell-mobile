{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE ImportQualifiedPost #-}
-- | Camera capture API for mobile platforms.
--
-- Provides session management (start\/stop), photo capture, and video
-- recording with file-path results delivered via callbacks.
-- On desktop (no platform bridge registered) the C stub dispatches
-- dummy file paths so that @cabal test@ exercises the callback path
-- without native code.
--
-- The camera session is owned by 'CameraState', not by the CameraView
-- widget.  The widget is a preview target — the active session attaches
-- its preview when the native renderer creates the view.
module HaskellMobile.Camera
  ( CameraSource(..)
  , CameraStatus(..)
  , CameraResult(..)
  , CameraState(..)
  , newCameraState
  , cameraSourceToInt
  , cameraStatusFromInt
  , startCameraSession
  , stopCameraSession
  , capturePhoto
  , startVideoCapture
  , stopVideoCapture
  , dispatchCameraResult
  )
where

import Data.IORef (IORef, newIORef, readIORef, writeIORef, modifyIORef')
import Data.Int (Int32)
import Data.IntMap.Strict (IntMap)
import Data.IntMap.Strict qualified as IntMap
import Data.Text (Text)
import Foreign.C.Types (CInt(..))
import Foreign.Ptr (Ptr, nullPtr)
import System.IO (hPutStrLn, stderr)

-- | Which camera to use.
data CameraSource
  = CameraBack   -- ^ Rear-facing camera.
  | CameraFront  -- ^ Front-facing (selfie) camera.
  deriving (Show, Eq)

-- | Outcome of a camera capture operation.
data CameraStatus
  = CameraSuccess          -- ^ Capture completed; file path is available.
  | CameraCancelled        -- ^ User cancelled the capture.
  | CameraPermissionDenied -- ^ Camera permission was denied.
  | CameraUnavailable      -- ^ Camera hardware is not available.
  | CameraError            -- ^ An unspecified error occurred.
  deriving (Show, Eq, Ord, Enum, Bounded)

-- | Result delivered to a capture callback.
data CameraResult = CameraResult
  { crStatus   :: CameraStatus
  , crFilePath :: Maybe Text
    -- ^ Absolute path to the captured file, or 'Nothing' on failure.
  } deriving (Show, Eq)

-- | Mutable state for the camera callback registry.
data CameraState = CameraState
  { csCallbacks  :: IORef (IntMap (CameraResult -> IO ()))
    -- ^ Map from requestId -> capture result callback.
  , csNextId     :: IORef Int32
    -- ^ Next available request ID.
  , csContextPtr :: IORef (Ptr ())
    -- ^ Opaque context pointer passed to the C bridge.
    -- Set by 'AppContext.newAppContext' after the 'StablePtr' is created.
  }

-- | Create a fresh 'CameraState' with no pending callbacks.
-- The context pointer is initially null and must be set via
-- 'csContextPtr' before calling any camera operation.
newCameraState :: IO CameraState
newCameraState = do
  callbacks  <- newIORef IntMap.empty
  nextId     <- newIORef 0
  contextPtr <- newIORef nullPtr
  pure CameraState
    { csCallbacks  = callbacks
    , csNextId     = nextId
    , csContextPtr = contextPtr
    }

-- | Convert a 'CameraSource' to its C integer code.
cameraSourceToInt :: CameraSource -> Int32
cameraSourceToInt CameraBack  = 0
cameraSourceToInt CameraFront = 1

-- | Convert a C bridge status code to 'CameraStatus'.
-- Returns 'Nothing' for unknown codes.
cameraStatusFromInt :: CInt -> Maybe CameraStatus
cameraStatusFromInt 0 = Just CameraSuccess
cameraStatusFromInt 1 = Just CameraCancelled
cameraStatusFromInt 2 = Just CameraPermissionDenied
cameraStatusFromInt 3 = Just CameraUnavailable
cameraStatusFromInt 4 = Just CameraError
cameraStatusFromInt _ = Nothing

-- | Start a camera session for the given source.
-- The session provides a live preview that the CameraView widget can display.
startCameraSession :: CameraState -> CameraSource -> IO ()
startCameraSession cameraState source = do
  ctx <- readIORef (csContextPtr cameraState)
  c_cameraStartSession ctx (fromIntegral (cameraSourceToInt source))

-- | Stop the active camera session.
-- Safe to call when no session is active (no-op).
stopCameraSession :: CameraState -> IO ()
stopCameraSession _cameraState =
  c_cameraStopSession

-- | Capture a photo. Registers the callback and calls the C bridge.
-- The callback fires when the platform responds (or synchronously on
-- desktop via the stub).
capturePhoto :: CameraState -> (CameraResult -> IO ()) -> IO ()
capturePhoto cameraState callback = do
  requestId <- readIORef (csNextId cameraState)
  modifyIORef' (csCallbacks cameraState) (IntMap.insert (fromIntegral requestId) callback)
  writeIORef (csNextId cameraState) (requestId + 1)
  ctx <- readIORef (csContextPtr cameraState)
  c_cameraCapturePhoto ctx (fromIntegral requestId)

-- | Start recording video. Registers the callback — the result is
-- delivered when 'stopVideoCapture' is called or the platform stops
-- recording.
startVideoCapture :: CameraState -> (CameraResult -> IO ()) -> IO ()
startVideoCapture cameraState callback = do
  requestId <- readIORef (csNextId cameraState)
  modifyIORef' (csCallbacks cameraState) (IntMap.insert (fromIntegral requestId) callback)
  writeIORef (csNextId cameraState) (requestId + 1)
  ctx <- readIORef (csContextPtr cameraState)
  c_cameraStartVideo ctx (fromIntegral requestId)

-- | Stop recording video. The callback registered by 'startVideoCapture'
-- will be fired with the video file path.
-- Safe to call when not recording (no-op).
stopVideoCapture :: CameraState -> IO ()
stopVideoCapture _cameraState =
  c_cameraStopVideo

-- | Dispatch a camera result from the platform back to the registered
-- Haskell callback. Removes the callback after firing.
-- Unknown request IDs or status codes are silently logged to stderr.
dispatchCameraResult :: CameraState -> CInt -> CInt -> Maybe Text -> IO ()
dispatchCameraResult cameraState requestId statusCode maybeFilePath =
  case cameraStatusFromInt statusCode of
    Nothing -> hPutStrLn stderr $
      "dispatchCameraResult: unknown status code " ++ show statusCode
    Just status -> do
      let reqKey = fromIntegral requestId
          result = CameraResult
            { crStatus   = status
            , crFilePath = case status of
                CameraSuccess -> maybeFilePath
                _             -> Nothing
            }
      callbacks <- readIORef (csCallbacks cameraState)
      case IntMap.lookup reqKey callbacks of
        Just callback -> do
          modifyIORef' (csCallbacks cameraState) (IntMap.delete reqKey)
          callback result
        Nothing -> hPutStrLn stderr $
          "dispatchCameraResult: unknown request ID " ++ show requestId

-- | FFI import: start a camera session via the C bridge.
foreign import ccall "camera_start_session"
  c_cameraStartSession :: Ptr () -> CInt -> IO ()

-- | FFI import: stop the camera session via the C bridge.
foreign import ccall "camera_stop_session"
  c_cameraStopSession :: IO ()

-- | FFI import: capture a photo via the C bridge.
foreign import ccall "camera_capture_photo"
  c_cameraCapturePhoto :: Ptr () -> CInt -> IO ()

-- | FFI import: start video recording via the C bridge.
foreign import ccall "camera_start_video"
  c_cameraStartVideo :: Ptr () -> CInt -> IO ()

-- | FFI import: stop video recording via the C bridge.
foreign import ccall "camera_stop_video"
  c_cameraStopVideo :: IO ()
