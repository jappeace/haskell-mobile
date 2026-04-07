{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE OverloadedStrings #-}
module HaskellMobile
  ( MobileApp(..)
  , UserState(..)
  , runMobileApp
  , getMobileApp
  -- FFI exports
  , haskellGreet
  , haskellCreateContext
  , haskellRenderUI
  , haskellOnUIEvent
  , haskellOnLifecycle
  , haskellOnPermissionResult
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
  )
where

import Control.Exception (SomeException, catch)
import Data.Text (pack)
import Foreign.C.String (CString, newCString, peekCString)
import Foreign.C.Types (CInt(..))
import Foreign.Ptr (Ptr, nullPtr, castPtr)
import HaskellMobile.AppContext (AppContext(..), newAppContext, freeAppContext, derefAppContext)
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
import HaskellMobile.Types (MobileApp(..), UserState(..), runMobileApp, getMobileApp)
import HaskellMobile.Widget (ButtonConfig(..), FontConfig(..), TextConfig(..), Widget(..))

-- | Wrap an IO action in a catch-all exception handler.
-- On failure, logs the exception, overwrites the registered app's view
-- with an error widget, and fires the user's 'onError' callback.
withExceptionHandler :: Ptr AppContext -> IO () -> IO ()
withExceptionHandler ctxPtr action =
  catch action (handleException ctxPtr)

-- | Handle an uncaught exception from an FFI entry point.
-- Overwrites the registered app's 'maView' with an error widget so
-- that subsequent renders show the error on screen. The error widget
-- includes a dismiss button that restores the original view.
-- Also logs via 'platformLog' and best-effort fires 'onError'.
handleException :: Ptr AppContext -> SomeException -> IO ()
handleException ctxPtr exc = do
  appCtx <- derefAppContext ctxPtr
  app <- getMobileApp
  let originalView = maView app
  runMobileApp app { maView = \_userState -> pure (errorWidget originalView exc) }
  platformLog ("Uncaught exception: " <> pack (show exc))
  renderWidget (acRenderState appCtx) (errorWidget originalView exc)
  fireUserErrorCallback exc

-- | Best-effort: read the registered app's 'onError' callback and fire it.
-- Catches any secondary exception so we never crash in the error handler.
fireUserErrorCallback :: SomeException -> IO ()
fireUserErrorCallback exc =
  catch
    (do app <- getMobileApp
        onError (maContext app) exc)
    (\secondaryExc ->
      platformLog ("onError callback failed: " <> pack (show (secondaryExc :: SomeException))))

-- | Render the current view: read the registered app and render its widget.
renderView :: Ptr AppContext -> IO ()
renderView ctxPtr = do
  appCtx <- derefAppContext ctxPtr
  app <- getMobileApp
  let userState = UserState { userPermissionState = acPermissionState appCtx }
  widget <- maView app userState
  renderWidget (acRenderState appCtx) widget

-- | A widget that displays an error message with a dismiss button.
-- The dismiss button restores the original view via a closure.
errorWidget :: (UserState -> IO Widget) -> SomeException -> Widget
errorWidget originalView exc = Column
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
          app <- getMobileApp
          runMobileApp app { maView = originalView }
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

-- | Create an 'AppContext' (bundling 'MobileContext' + 'RenderState' +
-- 'PermissionState') and return it as a typed pointer for C code.
-- Called by platform bridges after 'haskellRunMain'.
-- The context pointer is written into the 'PermissionState' so that
-- 'requestPermission' can thread it through to the C bridge.
-- Returns 'nullPtr' if the app is not registered or an exception occurs.
haskellCreateContext :: IO (Ptr AppContext)
haskellCreateContext =
  catch
    (do app <- getMobileApp
        newAppContext (maContext app))
    (\exc -> do
      platformLog ("haskellCreateContext failed: " <> pack (show (exc :: SomeException)))
      pure (castPtr nullPtr))

foreign export ccall haskellCreateContext :: IO (Ptr AppContext)

-- | Render the UI tree. Dereferences the context pointer to obtain the
-- 'RenderState', calls 'maView' from the registered 'MobileApp'
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
