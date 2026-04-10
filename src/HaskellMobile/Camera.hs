{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE ImportQualifiedPost #-}
-- | Camera capture API for mobile platforms.
--
-- Provides session management (start\/stop), photo capture, and video
-- recording with results delivered via callbacks.
-- On desktop (no platform bridge registered) the C stub dispatches
-- dummy results so that @cabal test@ exercises the callback path
-- without native code.
--
-- Photo captures deliver raw image bytes as a 'Picture'.
-- Video recording supports per-frame and per-audio-chunk
-- push callbacks that mirror the native Camera2\/AVFoundation model.
--
-- The camera session is owned by 'CameraState', not by the CameraView
-- widget.  The widget is a preview target — the active session attaches
-- its preview when the native renderer creates the view.
module HaskellMobile.Camera
  ( CameraSource(..)
  , CameraStatus(..)
  , Picture(..)
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
  , dispatchVideoFrame
  , dispatchAudioChunk
  )
where

import Data.ByteString (ByteString)
import Data.IORef (IORef, newIORef, readIORef, writeIORef, modifyIORef')
import Data.Int (Int32)
import Data.IntMap.Strict (IntMap)
import Data.IntMap.Strict qualified as IntMap
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
  = CameraSuccess          -- ^ Capture completed successfully.
  | CameraCancelled        -- ^ User cancelled the capture.
  | CameraPermissionDenied -- ^ Camera permission was denied.
  | CameraUnavailable      -- ^ Camera hardware is not available.
  | CameraError            -- ^ An unspecified error occurred.
  deriving (Show, Eq, Ord, Enum, Bounded)

-- | Raw image data from a photo capture or video frame.
data Picture = Picture
  { pictureWidth  :: Int
    -- ^ Image width in pixels.
  , pictureHeight :: Int
    -- ^ Image height in pixels.
  , pictureData   :: ByteString
    -- ^ JPEG-encoded image bytes.
  } deriving (Show, Eq)

-- | Result delivered to a capture callback.
data CameraResult = CameraResult
  { crStatus   :: CameraStatus
  , crPicture  :: Maybe Picture
    -- ^ Raw image data for photo captures, or 'Nothing' for video
    -- results and error results.
  } deriving (Show, Eq)

-- | Mutable state for the camera callback registry.
data CameraState = CameraState
  { csCallbacks      :: IORef (IntMap (CameraResult -> IO ()))
    -- ^ Map from requestId -> capture result callback.
  , csFrameCallbacks :: IORef (IntMap (Picture -> IO ()))
    -- ^ Map from requestId -> per-frame callback (video recording).
  , csAudioCallbacks :: IORef (IntMap (ByteString -> IO ()))
    -- ^ Map from requestId -> per-audio-chunk callback (video recording).
  , csNextId         :: IORef Int32
    -- ^ Next available request ID.
  , csContextPtr     :: IORef (Ptr ())
    -- ^ Opaque context pointer passed to the C bridge.
    -- Set by 'AppContext.newAppContext' after the 'StablePtr' is created.
  }

-- | Create a fresh 'CameraState' with no pending callbacks.
-- The context pointer is initially null and must be set via
-- 'csContextPtr' before calling any camera operation.
newCameraState :: IO CameraState
newCameraState = do
  callbacks      <- newIORef IntMap.empty
  frameCallbacks <- newIORef IntMap.empty
  audioCallbacks <- newIORef IntMap.empty
  nextId         <- newIORef 0
  contextPtr     <- newIORef nullPtr
  pure CameraState
    { csCallbacks      = callbacks
    , csFrameCallbacks = frameCallbacks
    , csAudioCallbacks = audioCallbacks
    , csNextId         = nextId
    , csContextPtr     = contextPtr
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

-- | Start recording video.  Registers three callbacks:
--
--   * A per-frame callback fired for each video frame ('Picture').
--   * A per-audio-chunk callback fired for each PCM audio chunk ('ByteString').
--   * A completion callback fired when recording stops ('CameraResult').
--
-- The frame and audio callbacks are removed when recording stops.
startVideoCapture :: CameraState
                  -> (Picture -> IO ())        -- ^ Called per video frame.
                  -> (ByteString -> IO ())     -- ^ Called per audio chunk.
                  -> (CameraResult -> IO ())   -- ^ Called when recording stops.
                  -> IO ()
startVideoCapture cameraState frameCallback audioCallback completionCallback = do
  requestId <- readIORef (csNextId cameraState)
  let reqKey = fromIntegral requestId
  modifyIORef' (csCallbacks cameraState) (IntMap.insert reqKey completionCallback)
  modifyIORef' (csFrameCallbacks cameraState) (IntMap.insert reqKey frameCallback)
  modifyIORef' (csAudioCallbacks cameraState) (IntMap.insert reqKey audioCallback)
  writeIORef (csNextId cameraState) (requestId + 1)
  ctx <- readIORef (csContextPtr cameraState)
  c_cameraStartVideo ctx (fromIntegral requestId)

-- | Stop recording video. The callback registered by 'startVideoCapture'
-- will be fired with a completion result.
-- Safe to call when not recording (no-op).
stopVideoCapture :: CameraState -> IO ()
stopVideoCapture _cameraState =
  c_cameraStopVideo

-- | Dispatch a camera result from the platform back to the registered
-- Haskell callback.  Removes the result callback (and any associated
-- frame\/audio callbacks) after firing.
-- Unknown request IDs or status codes are silently logged to stderr.
dispatchCameraResult :: CameraState -> CInt -> CInt
                     -> Maybe ByteString -> CInt -> CInt
                     -> IO ()
dispatchCameraResult cameraState requestId statusCode
                     maybeImageData imageWidth imageHeight =
  case cameraStatusFromInt statusCode of
    Nothing -> hPutStrLn stderr $
      "dispatchCameraResult: unknown status code " ++ show statusCode
    Just status -> do
      let reqKey = fromIntegral requestId
          maybePicture = case status of
            CameraSuccess -> case maybeImageData of
              Just imageBytes -> Just Picture
                { pictureWidth  = fromIntegral imageWidth
                , pictureHeight = fromIntegral imageHeight
                , pictureData   = imageBytes
                }
              Nothing -> Nothing
            _ -> Nothing
          result = CameraResult
            { crStatus   = status
            , crPicture  = maybePicture
            }
      callbacks <- readIORef (csCallbacks cameraState)
      case IntMap.lookup reqKey callbacks of
        Just callback -> do
          modifyIORef' (csCallbacks cameraState) (IntMap.delete reqKey)
          modifyIORef' (csFrameCallbacks cameraState) (IntMap.delete reqKey)
          modifyIORef' (csAudioCallbacks cameraState) (IntMap.delete reqKey)
          callback result
        Nothing -> hPutStrLn stderr $
          "dispatchCameraResult: unknown request ID " ++ show requestId

-- | Dispatch a video frame from the platform to the registered frame
-- callback.  Does not remove the callback — it stays active until
-- recording stops.
dispatchVideoFrame :: CameraState -> CInt -> ByteString -> CInt -> CInt -> IO ()
dispatchVideoFrame cameraState requestId frameBytes frameWidth frameHeight = do
  let reqKey = fromIntegral requestId
      picture = Picture
        { pictureWidth  = fromIntegral frameWidth
        , pictureHeight = fromIntegral frameHeight
        , pictureData   = frameBytes
        }
  frameCallbacks <- readIORef (csFrameCallbacks cameraState)
  case IntMap.lookup reqKey frameCallbacks of
    Just callback -> callback picture
    Nothing -> hPutStrLn stderr $
      "dispatchVideoFrame: unknown request ID " ++ show requestId

-- | Dispatch an audio chunk from the platform to the registered audio
-- callback.  Does not remove the callback — it stays active until
-- recording stops.
dispatchAudioChunk :: CameraState -> CInt -> ByteString -> IO ()
dispatchAudioChunk cameraState requestId audioBytes = do
  let reqKey = fromIntegral requestId
  audioCallbacks <- readIORef (csAudioCallbacks cameraState)
  case IntMap.lookup reqKey audioCallbacks of
    Just callback -> callback audioBytes
    Nothing -> hPutStrLn stderr $
      "dispatchAudioChunk: unknown request ID " ++ show requestId

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
