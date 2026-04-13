{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE OverloadedStrings #-}
-- |
-- Module      : Hatter
-- Description : Cross-platform mobile UI framework for Haskell
--
-- Hatter lets you build native mobile apps in Haskell.  Define your UI
-- as a pure 'Widget' tree, wire up callbacks with 'Action' handles, and
-- the framework takes care of rendering on Android, iOS, and watchOS.
--
-- = Getting started
--
-- @
-- import Hatter
-- import Hatter.Widget
--
-- main :: IO ()
-- main = do
--   acts <- 'newActionState'
--   greet <- 'runActionM' acts $ 'createAction' (putStrLn \"tapped!\")
--   _ <- 'startMobileApp' MobileApp
--     { maContext     = 'defaultMobileContext'
--     , maView        = \\_ -> pure ('button' greet \"Tap me\")
--     , maActionState = acts
--     }
--   pure ()
-- @
--
-- = Platform subsystems
--
-- Domain-specific APIs live in their own modules.  Import them when you
-- need a particular capability:
--
-- * "Hatter.Permission" — runtime permission requests
-- * "Hatter.SecureStorage" — encrypted key-value storage
-- * "Hatter.Ble" — Bluetooth Low Energy scanning
-- * "Hatter.Dialog" — native alert dialogs
-- * "Hatter.Location" — GPS \/ location updates
-- * "Hatter.AuthSession" — OAuth browser sessions
-- * "Hatter.Camera" — photo & video capture
-- * "Hatter.BottomSheet" — modal bottom sheets
-- * "Hatter.Http" — HTTP requests
-- * "Hatter.NetworkStatus" — connectivity monitoring
-- * "Hatter.Locale" — device locale & language
-- * "Hatter.I18n" — internationalisation helpers
-- * "Hatter.FilesDir" — app-private file storage path
-- * "Hatter.AppContext" — low-level context pointer (advanced)
module Hatter
  ( -- * App setup
    MobileApp(..)
  , UserState(..)
  , startMobileApp
    -- * Widget
  , Widget(..)
  , WidgetStyle(..)
  , defaultStyle
  , ButtonConfig(..)
  , TextConfig(..)
  , FontConfig(..)
  , TextInputConfig(..)
  , InputType(..)
  , ImageConfig(..)
  , ImageSource(..)
  , ResourceName(..)
  , ScaleType(..)
  , TextAlignment(..)
  , WebViewConfig(..)
  , MapViewConfig(..)
  , Color(..)
  , colorFromText
  , colorToHex
    -- ** Smart constructors
  , button
  , text
    -- * Actions
  , Action(..)
  , OnChange(..)
  , ActionState
  , ActionM
  , createAction
  , createOnChange
  , newActionState
  , runActionM
    -- * Animation
  , Easing(..)
  , AnimatedConfig(..)
    -- * Lifecycle
  , LifecycleEvent(..)
  , MobileContext(..)
  , defaultMobileContext
  , loggingMobileContext
  , platformLog
    -- * Error handling
  , errorWidget
    -- * Internal
    -- | FFI entry points used by the test suite.  Application code
    -- should not need them.  The remaining @foreign export ccall@
    -- functions (permission, BLE, camera, etc.) are visible to the
    -- C linker but not re-exported as Haskell API.
  , haskellGreet
  , haskellRenderUI
  , haskellOnUIEvent
  , haskellOnLifecycle
  )
where

import Control.Exception (SomeException, catch)
import Data.IORef (readIORef, writeIORef)
import Data.Text (Text, pack)
import Foreign.C.String (CString, newCString, peekCString)
import Foreign.C.Types (CDouble(..), CInt(..))
import Foreign.Ptr (Ptr, castPtr, nullPtr)
import Data.ByteString qualified as BS
import Data.Word (Word8)
import Hatter.Action
  ( Action(..)
  , OnChange(..)
  , ActionState
  , ActionM
  , createAction
  , createOnChange
  , newActionState
  , runActionM
  )
import Hatter.Animation (dispatchAnimationFrame)
import Hatter.AppContext (AppContext(..), newAppContext, derefAppContext)
import Hatter.AuthSession (dispatchAuthSessionResult)
import Hatter.Ble (dispatchBleScanResult)
import Hatter.BottomSheet (dispatchBottomSheetResult)
import Hatter.Camera
  ( dispatchCameraResult
  , dispatchVideoFrame
  , dispatchAudioChunk
  )
import Hatter.Dialog (dispatchDialogResult)
import Hatter.Http (dispatchHttpResult)
import Hatter.Lifecycle
  ( LifecycleEvent(..)
  , MobileContext(..)
  , defaultMobileContext
  , loggingMobileContext
  , platformLog
  , lifecycleFromInt
  )
import Hatter.Location (dispatchLocationUpdate)
import Hatter.NetworkStatus (dispatchNetworkStatusChange)
import Hatter.Permission (dispatchPermissionResult)
import Hatter.Render (renderWidget, dispatchEvent, dispatchTextEvent)
import Hatter.SecureStorage (dispatchSecureStorageResult)
import Hatter.Types (MobileApp(..), UserState(..))
import Hatter.Widget
  ( AnimatedConfig(..)
  , ButtonConfig(..)
  , Color(..)
  , Easing(..)
  , FontConfig(..)
  , ImageConfig(..)
  , ImageSource(..)
  , InputType(..)
  , MapViewConfig(..)
  , ResourceName(..)
  , ScaleType(..)
  , TextAlignment(..)
  , TextConfig(..)
  , TextInputConfig(..)
  , WebViewConfig(..)
  , Widget(..)
  , WidgetStyle(..)
  , button
  , colorFromText
  , colorToHex
  , defaultStyle
  , text
  )

-- | Create an 'AppContext' from a 'MobileApp' and return it as a typed
-- pointer suitable for the C FFI. This is the user-facing API: the user's
-- @main@ calls this to initialise the framework.
startMobileApp :: MobileApp -> IO (Ptr AppContext)
startMobileApp = newAppContext

-- | Wrap an IO action in a catch-all exception handler.
-- On failure, logs the exception, overwrites the context's view
-- with an error widget, and fires the user's 'onError' callback.
withExceptionHandler :: Ptr AppContext -> IO () -> IO ()
withExceptionHandler ctxPtr action =
  catch action (handleException ctxPtr)

-- | Handle an uncaught exception from an FFI entry point.
-- Overwrites the context's view function with an error widget so
-- that subsequent renders show the error on screen. The dismiss
-- button uses a pre-registered 'Action' handle; we write the real
-- restore logic into 'acDismissRef'.
-- Also logs via 'platformLog' and best-effort fires 'onError'.
handleException :: Ptr AppContext -> SomeException -> IO ()
handleException ctxPtr exc = do
  appCtx <- derefAppContext ctxPtr
  originalView <- readIORef (acViewFunction appCtx)
  let dismissAction = acDismissAction appCtx
  -- Write the real dismiss logic: restore the original view function.
  writeIORef (acDismissRef appCtx)
    (writeIORef (acViewFunction appCtx) originalView)
  writeIORef (acViewFunction appCtx)
    (\_userState -> pure (errorWidget dismissAction exc))
  platformLog ("Uncaught exception: " <> pack (show exc))
  renderWidget (acRenderState appCtx)
    (errorWidget dismissAction exc)
  fireUserErrorCallback appCtx exc

-- | Best-effort: read the context's 'onError' callback and fire it.
-- Catches any secondary exception so we never crash in the error handler.
fireUserErrorCallback :: AppContext -> SomeException -> IO ()
fireUserErrorCallback appCtx exc =
  catch
    (onError (acMobileContext appCtx) exc)
    (\secondaryExc ->
      platformLog ("onError callback failed: " <> pack (show (secondaryExc :: SomeException))))

-- | Render the current view: read the view function from AppContext and
-- render its widget.
renderView :: Ptr AppContext -> IO ()
renderView ctxPtr = do
  appCtx <- derefAppContext ctxPtr
  viewFunction <- readIORef (acViewFunction appCtx)
  let userState = UserState
        { userPermissionState    = acPermissionState appCtx
        , userSecureStorageState = acSecureStorageState appCtx
        , userBleState           = acBleState appCtx
        , userDialogState        = acDialogState appCtx
        , userLocationState      = acLocationState appCtx
        , userAuthSessionState   = acAuthSessionState appCtx
        , userCameraState        = acCameraState appCtx
        , userBottomSheetState   = acBottomSheetState appCtx
        , userHttpState              = acHttpState appCtx
        , userNetworkStatusState    = acNetworkStatusState appCtx
        , userAnimationState     = acAnimationState appCtx
        }
  widget <- viewFunction userState
  renderWidget (acRenderState appCtx) widget

-- | A widget that displays an error message with a dismiss button.
-- The dismiss button uses a pre-registered 'Action' handle whose
-- closure is populated by the exception handler.
errorWidget :: Action -> SomeException -> Widget
errorWidget dismissAction exc = Column
  [ Text TextConfig
      { tcLabel      = "An error occurred"
      , tcFontConfig = Just (FontConfig 20.0)
      }
  , Text TextConfig
      { tcLabel      = pack (show exc)
      , tcFontConfig = Nothing
      }
  , Button ButtonConfig
      { bcLabel      = "Dismiss"
      , bcAction     = dismissAction
      , bcFontConfig = Nothing
      }
  ]

-- | Takes a name as CString, returns "Hello from Haskell, <name>!" as CString.
-- Caller is responsible for freeing the returned CString.
haskellGreet :: CString -> IO CString
haskellGreet cname = do
  name <- peekCString cname
  newCString ("Hello from Haskell, " ++ name ++ "!")

foreign export ccall haskellGreet :: CString -> IO CString

-- | Render the UI tree. Dereferences the context pointer to obtain the
-- 'RenderState', reads the view function from 'AppContext'
-- to get the widget description, then issues ui_* calls through the
-- registered bridge callbacks. Catches exceptions and shows error widget.
haskellRenderUI :: Ptr AppContext -> IO ()
haskellRenderUI ctxPtr =
  withExceptionHandler ctxPtr (renderView ctxPtr)

foreign export ccall haskellRenderUI :: Ptr AppContext -> IO ()

-- | Handle a UI event from native code. Dispatches the callback
-- identified by @callbackId@, then re-renders the UI.
haskellOnUIEvent :: Ptr AppContext -> CInt -> IO ()
haskellOnUIEvent ctxPtr callbackId =
  withExceptionHandler ctxPtr $ do
    appCtx <- derefAppContext ctxPtr
    dispatchEvent (acRenderState appCtx) (fromIntegral callbackId)
    renderView ctxPtr

foreign export ccall haskellOnUIEvent :: Ptr AppContext -> CInt -> IO ()

-- | Handle a text change event from native code. Dispatches the callback
-- identified by @callbackId@ with the new text value. Does NOT re-render
-- to avoid EditText cursor/flicker issues on Android.
haskellOnUITextChange :: Ptr AppContext -> CInt -> CString -> IO ()
haskellOnUITextChange ctxPtr callbackId cstr =
  withExceptionHandler ctxPtr $ do
    appCtx <- derefAppContext ctxPtr
    str <- peekCString cstr
    dispatchTextEvent (acRenderState appCtx) (fromIntegral callbackId) (pack str)

foreign export ccall haskellOnUITextChange :: Ptr AppContext -> CInt -> CString -> IO ()

-- | Handle a permission result from native code. Dispatches to the
-- callback registered by 'Hatter.Permission.requestPermission'.
haskellOnPermissionResult :: Ptr AppContext -> CInt -> CInt -> IO ()
haskellOnPermissionResult ctxPtr requestId statusCode =
  withExceptionHandler ctxPtr $ do
    appCtx <- derefAppContext ctxPtr
    dispatchPermissionResult (acPermissionState appCtx) requestId statusCode

foreign export ccall haskellOnPermissionResult :: Ptr AppContext -> CInt -> CInt -> IO ()

-- | Handle a BLE scan result from native code. Dispatches to the
-- callback registered by 'Hatter.Ble.startBleScan'.
haskellOnBleScanResult :: Ptr AppContext -> CString -> CString -> CInt -> IO ()
haskellOnBleScanResult ctxPtr cName cAddr cRssi =
  withExceptionHandler ctxPtr $ do
    appCtx <- derefAppContext ctxPtr
    dispatchBleScanResult (acBleState appCtx) cName cAddr cRssi

foreign export ccall haskellOnBleScanResult :: Ptr AppContext -> CString -> CString -> CInt -> IO ()

-- | Handle a dialog result from native code. Dispatches to the
-- callback registered by 'Hatter.Dialog.showDialog'.
haskellOnDialogResult :: Ptr AppContext -> CInt -> CInt -> IO ()
haskellOnDialogResult ctxPtr requestId actionCode =
  withExceptionHandler ctxPtr $ do
    appCtx <- derefAppContext ctxPtr
    dispatchDialogResult (acDialogState appCtx) requestId actionCode

foreign export ccall haskellOnDialogResult :: Ptr AppContext -> CInt -> CInt -> IO ()

-- | Handle a location update from native code. Dispatches to the
-- callback registered by 'Hatter.Location.startLocationUpdates'.
haskellOnLocationUpdate :: Ptr AppContext -> CDouble -> CDouble -> CDouble -> CDouble -> IO ()
haskellOnLocationUpdate ctxPtr cLat cLon cAlt cAcc =
  withExceptionHandler ctxPtr $ do
    appCtx <- derefAppContext ctxPtr
    dispatchLocationUpdate (acLocationState appCtx) cLat cLon cAlt cAcc

foreign export ccall haskellOnLocationUpdate :: Ptr AppContext -> CDouble -> CDouble -> CDouble -> CDouble -> IO ()

-- | FFI entry point called from platform code.
-- Takes a context pointer and an event code.
-- Dereferences as 'AppContext' and dispatches to the 'onLifecycle' callback
-- of the inner 'MobileContext'. Unknown event codes are silently ignored.
-- Catches exceptions and fires 'onError'.
haskellOnLifecycle :: Ptr AppContext -> CInt -> IO ()
haskellOnLifecycle ctxPtr code =
  withExceptionHandler ctxPtr $
    case lifecycleFromInt code of
      Just event -> do
        appCtx <- derefAppContext ctxPtr
        onLifecycle (acMobileContext appCtx) event
      Nothing -> pure ()

foreign export ccall haskellOnLifecycle :: Ptr AppContext -> CInt -> IO ()

-- | Handle a secure storage result from native code. Dispatches to the
-- callback registered by 'Hatter.SecureStorage.secureStorageWrite',
-- 'Hatter.SecureStorage.secureStorageRead', or
-- 'Hatter.SecureStorage.secureStorageDelete'.  The @cValue@ parameter is non-null only for
-- successful read operations.
haskellOnSecureStorageResult :: Ptr AppContext -> CInt -> CInt -> CString -> IO ()
haskellOnSecureStorageResult ctxPtr requestId statusCode cValue =
  withExceptionHandler ctxPtr $ do
    appCtx <- derefAppContext ctxPtr
    maybeValue <- peekOptionalCString cValue
    dispatchSecureStorageResult (acSecureStorageState appCtx) requestId statusCode maybeValue

foreign export ccall haskellOnSecureStorageResult :: Ptr AppContext -> CInt -> CInt -> CString -> IO ()

-- | Handle an auth session result from native code. Dispatches to the
-- callback registered by 'Hatter.AuthSession.startAuthSession'. The @cRedirectUrl@ parameter
-- is non-null only for successful sessions. The @cErrorMsg@ parameter
-- is non-null only for error sessions.
haskellOnAuthSessionResult :: Ptr AppContext -> CInt -> CInt -> CString -> CString -> IO ()
haskellOnAuthSessionResult ctxPtr requestId statusCode cRedirectUrl cErrorMsg =
  withExceptionHandler ctxPtr $ do
    appCtx <- derefAppContext ctxPtr
    maybeRedirectUrl <- peekOptionalCString cRedirectUrl
    maybeErrorMsg <- peekOptionalCString cErrorMsg
    dispatchAuthSessionResult (acAuthSessionState appCtx) requestId statusCode maybeRedirectUrl maybeErrorMsg

foreign export ccall haskellOnAuthSessionResult :: Ptr AppContext -> CInt -> CInt -> CString -> CString -> IO ()

-- | Handle a camera result from native code. Dispatches to the
-- callback registered by 'Hatter.Camera.capturePhoto' or 'Hatter.Camera.startVideoCapture'.
-- The @imageDataPtr@/@imageDataLen@/@width@/@height@ parameters carry
-- raw JPEG bytes for photo captures; null\/0 for video completions and
-- error results.
haskellOnCameraResult :: Ptr AppContext -> CInt -> CInt
                      -> Ptr Word8 -> CInt -> CInt -> CInt -> IO ()
haskellOnCameraResult ctxPtr requestId statusCode
                      imageDataPtr imageDataLen width height =
  withExceptionHandler ctxPtr $ do
    appCtx <- derefAppContext ctxPtr
    maybeImageData <- if imageDataPtr == nullPtr || imageDataLen <= 0
      then pure Nothing
      else Just <$> BS.packCStringLen (castPtr imageDataPtr, fromIntegral imageDataLen)
    dispatchCameraResult (acCameraState appCtx) requestId statusCode
      maybeImageData width height

foreign export ccall haskellOnCameraResult
  :: Ptr AppContext -> CInt -> CInt
  -> Ptr Word8 -> CInt -> CInt -> CInt -> IO ()

-- | Handle a video frame from native code. Dispatches to the
-- per-frame callback registered by 'Hatter.Camera.startVideoCapture'.
haskellOnVideoFrame :: Ptr AppContext -> CInt
                    -> Ptr Word8 -> CInt -> CInt -> CInt -> IO ()
haskellOnVideoFrame ctxPtr requestId frameDataPtr frameDataLen width height =
  withExceptionHandler ctxPtr $ do
    appCtx <- derefAppContext ctxPtr
    frameBytes <- BS.packCStringLen (castPtr frameDataPtr, fromIntegral frameDataLen)
    dispatchVideoFrame (acCameraState appCtx) requestId frameBytes width height

foreign export ccall haskellOnVideoFrame
  :: Ptr AppContext -> CInt -> Ptr Word8 -> CInt -> CInt -> CInt -> IO ()

-- | Handle an audio chunk from native code. Dispatches to the
-- per-audio-chunk callback registered by 'Hatter.Camera.startVideoCapture'.
haskellOnAudioChunk :: Ptr AppContext -> CInt
                    -> Ptr Word8 -> CInt -> IO ()
haskellOnAudioChunk ctxPtr requestId audioDataPtr audioDataLen =
  withExceptionHandler ctxPtr $ do
    appCtx <- derefAppContext ctxPtr
    audioBytes <- BS.packCStringLen (castPtr audioDataPtr, fromIntegral audioDataLen)
    dispatchAudioChunk (acCameraState appCtx) requestId audioBytes

foreign export ccall haskellOnAudioChunk
  :: Ptr AppContext -> CInt -> Ptr Word8 -> CInt -> IO ()
-- | Handle a bottom sheet result from native code. Dispatches to the
-- callback registered by 'Hatter.BottomSheet.showBottomSheet'.
haskellOnBottomSheetResult :: Ptr AppContext -> CInt -> CInt -> IO ()
haskellOnBottomSheetResult ctxPtr requestId actionCode =
  withExceptionHandler ctxPtr $ do
    appCtx <- derefAppContext ctxPtr
    dispatchBottomSheetResult (acBottomSheetState appCtx) requestId actionCode

foreign export ccall haskellOnBottomSheetResult :: Ptr AppContext -> CInt -> CInt -> IO ()

-- | Handle an HTTP result from native code. Dispatches to the
-- callback registered by 'Hatter.Http.performRequest'. The @cHeaders@ parameter
-- is newline-delimited key-value pairs for success, or an error message
-- for network errors. The @bodyPtr@/@bodyLen@ carry the response body.
haskellOnHttpResult :: Ptr AppContext -> CInt -> CInt -> CInt
                    -> CString -> Ptr Word8 -> CInt -> IO ()
haskellOnHttpResult ctxPtr requestId resultCode httpStatus
                    cHeaders bodyPtr bodyLen =
  withExceptionHandler ctxPtr $ do
    appCtx <- derefAppContext ctxPtr
    maybeHeaders <- peekOptionalCString cHeaders
    responseBody <- if bodyPtr == nullPtr || bodyLen <= 0
      then pure BS.empty
      else BS.packCStringLen (castPtr bodyPtr, fromIntegral bodyLen)
    dispatchHttpResult (acHttpState appCtx) requestId resultCode httpStatus
      maybeHeaders responseBody

foreign export ccall haskellOnHttpResult
  :: Ptr AppContext -> CInt -> CInt -> CInt
  -> CString -> Ptr Word8 -> CInt -> IO ()

-- | Handle a network status change from native code. Dispatches to the
-- callback registered by 'Hatter.NetworkStatus.startNetworkMonitoring'.
haskellOnNetworkStatusChange :: Ptr AppContext -> CInt -> CInt -> IO ()
haskellOnNetworkStatusChange ctxPtr cConnected cTransport =
  withExceptionHandler ctxPtr $ do
    appCtx <- derefAppContext ctxPtr
    dispatchNetworkStatusChange (acNetworkStatusState appCtx) cConnected cTransport

foreign export ccall haskellOnNetworkStatusChange :: Ptr AppContext -> CInt -> CInt -> IO ()

-- | Handle an animation frame from native code.  Ticks all active tweens,
-- applies interpolated properties, then re-renders the UI so that the
-- user's view function can confirm the target (Eq match → no new tween).
haskellOnAnimationFrame :: Ptr AppContext -> CDouble -> IO ()
haskellOnAnimationFrame ctxPtr (CDouble timestampMs) =
  withExceptionHandler ctxPtr $ do
    appCtx <- derefAppContext ctxPtr
    dispatchAnimationFrame (acAnimationState appCtx) timestampMs
    renderView ctxPtr

foreign export ccall haskellOnAnimationFrame :: Ptr AppContext -> CDouble -> IO ()

-- | Peek an optional CString: returns 'Nothing' for null pointers,
-- 'Just' with the decoded 'Text' otherwise.
peekOptionalCString :: CString -> IO (Maybe Text)
peekOptionalCString cstr
  | cstr == nullPtr = pure Nothing
  | otherwise       = Just . pack <$> peekCString cstr
