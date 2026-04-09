{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE OverloadedStrings #-}
module HaskellMobile
  ( MobileApp(..)
  , UserState(..)
  , startMobileApp
  -- FFI exports
  , haskellGreet
  , haskellRenderUI
  , haskellOnUIEvent
  , haskellOnLifecycle
  , haskellOnPermissionResult
  , haskellOnSecureStorageResult
  , haskellOnBleScanResult
  -- Error handling
  , errorWidget
  -- Re-exports from Lifecycle
  , LifecycleEvent(..)
  , MobileContext(..)
  , defaultMobileContext
  , loggingMobileContext
  , platformLog
  , newMobileContext
  , freeMobileContext
  -- Re-exports from AppContext
  , AppContext(..)
  , newAppContext
  , freeAppContext
  , derefAppContext
  -- Re-exports from Locale
  , Language(..)
  , Locale(..)
  , LocaleFailure(..)
  , getSystemLocale
  , parseLocale
  , localeToText
  , languageToCode
  , languageFromCode
  -- Re-exports from I18n
  , Key(..)
  , TranslateFailure(..)
  , translate
  -- Re-exports from Permission
  , Permission(..)
  , PermissionStatus(..)
  , PermissionState(..)
  , requestPermission
  , checkPermission
  -- Re-exports from SecureStorage
  , SecureStorageStatus(..)
  , SecureStorageState(..)
  , secureStorageWrite
  , secureStorageRead
  , secureStorageDelete
  -- Re-exports from Ble
  , BleAdapterStatus(..)
  , BleScanResult(..)
  , BleState(..)
  , checkBleAdapter
  , startBleScan
  , stopBleScan
  )
where

import Control.Exception (SomeException, catch)
import Data.IORef (readIORef, writeIORef)
import Data.Text (Text, pack)
import Foreign.C.String (CString, newCString, peekCString)
import Foreign.C.Types (CInt(..))
import Foreign.Ptr (Ptr, nullPtr)
import HaskellMobile.AppContext (AppContext(..), newAppContext, freeAppContext, derefAppContext)
import HaskellMobile.Ble
  ( BleAdapterStatus(..)
  , BleScanResult(..)
  , BleState(..)
  , checkBleAdapter
  , startBleScan
  , stopBleScan
  , dispatchBleScanResult
  )
import HaskellMobile.Lifecycle
  ( LifecycleEvent(..)
  , MobileContext(..)
  , defaultMobileContext
  , loggingMobileContext
  , platformLog
  , newMobileContext
  , freeMobileContext
  , lifecycleFromInt
  )
import HaskellMobile.I18n (Key(..), TranslateFailure(..), translate)
import HaskellMobile.Locale (Language(..), Locale(..), LocaleFailure(..), getSystemLocale, parseLocale, localeToText, languageToCode, languageFromCode)
import HaskellMobile.Permission
  ( Permission(..)
  , PermissionStatus(..)
  , PermissionState(..)
  , requestPermission
  , checkPermission
  , dispatchPermissionResult
  )
import HaskellMobile.Render (renderWidget, dispatchEvent, dispatchTextEvent)
import HaskellMobile.SecureStorage
  ( SecureStorageStatus(..)
  , SecureStorageState(..)
  , secureStorageWrite
  , secureStorageRead
  , secureStorageDelete
  , dispatchSecureStorageResult
  )
import HaskellMobile.Types (MobileApp(..), UserState(..))
import HaskellMobile.Widget (ButtonConfig(..), FontConfig(..), TextConfig(..), Widget(..))

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
-- that subsequent renders show the error on screen. The error widget
-- includes a dismiss button that restores the original view.
-- Also logs via 'platformLog' and best-effort fires 'onError'.
handleException :: Ptr AppContext -> SomeException -> IO ()
handleException ctxPtr exc = do
  appCtx <- derefAppContext ctxPtr
  originalView <- readIORef (acViewFunction appCtx)
  writeIORef (acViewFunction appCtx)
    (\_userState -> pure (errorWidget ctxPtr originalView exc))
  platformLog ("Uncaught exception: " <> pack (show exc))
  renderWidget (acRenderState appCtx)
    (errorWidget ctxPtr originalView exc)
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
        }
  widget <- viewFunction userState
  renderWidget (acRenderState appCtx) widget

-- | A widget that displays an error message with a dismiss button.
-- The dismiss button restores the original view via a closure.
errorWidget :: Ptr AppContext -> (UserState -> IO Widget) -> SomeException -> Widget
errorWidget ctxPtr originalView exc = Column
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
      , bcAction     = do
          appCtx <- derefAppContext ctxPtr
          writeIORef (acViewFunction appCtx) originalView
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
-- callback registered by 'requestPermission'.
haskellOnPermissionResult :: Ptr AppContext -> CInt -> CInt -> IO ()
haskellOnPermissionResult ctxPtr requestId statusCode =
  withExceptionHandler ctxPtr $ do
    appCtx <- derefAppContext ctxPtr
    dispatchPermissionResult (acPermissionState appCtx) requestId statusCode

foreign export ccall haskellOnPermissionResult :: Ptr AppContext -> CInt -> CInt -> IO ()

-- | Handle a BLE scan result from native code. Dispatches to the
-- callback registered by 'startBleScan'.
haskellOnBleScanResult :: Ptr AppContext -> CString -> CString -> CInt -> IO ()
haskellOnBleScanResult ctxPtr cName cAddr cRssi =
  withExceptionHandler ctxPtr $ do
    appCtx <- derefAppContext ctxPtr
    dispatchBleScanResult (acBleState appCtx) cName cAddr cRssi

foreign export ccall haskellOnBleScanResult :: Ptr AppContext -> CString -> CString -> CInt -> IO ()

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
-- callback registered by 'secureStorageWrite', 'secureStorageRead', or
-- 'secureStorageDelete'.  The @cValue@ parameter is non-null only for
-- successful read operations.
haskellOnSecureStorageResult :: Ptr AppContext -> CInt -> CInt -> CString -> IO ()
haskellOnSecureStorageResult ctxPtr requestId statusCode cValue =
  withExceptionHandler ctxPtr $ do
    appCtx <- derefAppContext ctxPtr
    maybeValue <- peekOptionalCString cValue
    dispatchSecureStorageResult (acSecureStorageState appCtx) requestId statusCode maybeValue

foreign export ccall haskellOnSecureStorageResult :: Ptr AppContext -> CInt -> CInt -> CString -> IO ()

-- | Peek an optional CString: returns 'Nothing' for null pointers,
-- 'Just' with the decoded 'Text' otherwise.
peekOptionalCString :: CString -> IO (Maybe Text)
peekOptionalCString cstr
  | cstr == nullPtr = pure Nothing
  | otherwise       = Just . pack <$> peekCString cstr
