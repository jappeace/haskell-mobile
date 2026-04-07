{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE OverloadedStrings #-}
module HaskellMobile
  ( MobileApp(..)
  , runMobileApp
  , getMobileApp
  -- FFI exports
  , haskellGreet
  , haskellCreateContext
  , haskellRenderUI
  , haskellOnUIEvent
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
  -- App state
  , AppState(..)
  , globalAppState
  )
where

import Control.Exception (SomeException, catch)
import Data.Text (pack)
import Foreign.C.String (CString, newCString, peekCString)
import Foreign.C.Types (CInt(..))
import Foreign.Ptr (Ptr, nullPtr)
import Foreign.StablePtr (castStablePtrToPtr)
import HaskellMobile.Lifecycle
  ( LifecycleEvent(..)
  , MobileContext(..)
  , defaultMobileContext
  , loggingMobileContext
  , platformLog
  , newMobileContext
  , freeMobileContext
  )
import HaskellMobile.I18n (Key(..), TranslateFailure(..), translate)
import HaskellMobile.Locale (Language(..), Locale(..), LocaleFailure(..), getSystemLocale, parseLocale, localeToText, languageToCode, languageFromCode)
import HaskellMobile.Permission
  ( Permission(..)
  , PermissionStatus(..)
  , PermissionState(..)
  , newPermissionState
  , requestPermission
  , checkPermission
  , dispatchPermissionResult
  )
import HaskellMobile.Render (RenderState, newRenderState, renderWidget, dispatchEvent, dispatchTextEvent)
import HaskellMobile.Types (MobileApp(..), runMobileApp, getMobileApp)
import HaskellMobile.Widget (ButtonConfig(..), FontConfig(..), TextConfig(..), Widget(..))
import System.IO.Unsafe (unsafePerformIO)

-- | Combined runtime state for the app.
-- Single global replaces individual globals for render and permission state.
data AppState = AppState
  { appRenderState     :: RenderState
  , appPermissionState :: PermissionState
  }

-- | The one global mutable state, initialised once on first use.
-- Safe because all UI calls happen on the main thread.
globalAppState :: AppState
globalAppState = unsafePerformIO $
  AppState <$> newRenderState <*> newPermissionState
{-# NOINLINE globalAppState #-}

-- | Wrap an IO action in a catch-all exception handler.
-- On failure, logs the exception, overwrites the registered app's view
-- with an error widget, and fires the user's 'onError' callback.
withExceptionHandler :: IO () -> IO ()
withExceptionHandler action =
  catch action handleException

-- | Handle an uncaught exception from an FFI entry point.
-- Overwrites the registered app's 'maView' with an error widget so
-- that subsequent renders show the error on screen. The error widget
-- includes a dismiss button that restores the original view.
-- Also logs via 'platformLog' and best-effort fires 'onError'.
handleException :: SomeException -> IO ()
handleException exc = do
  app <- getMobileApp
  let originalView = maView app
  runMobileApp app { maView = pure (errorWidget originalView exc) }
  platformLog ("Uncaught exception: " <> pack (show exc))
  renderWidget (appRenderState globalAppState) (errorWidget originalView exc)
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
renderView :: IO ()
renderView = do
  app <- getMobileApp
  widget <- maView app
  renderWidget (appRenderState globalAppState) widget

-- | A widget that displays an error message with a dismiss button.
-- The dismiss button restores the original view via a closure.
errorWidget :: IO Widget -> SomeException -> Widget
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

-- | Create a 'MobileContext' and return it as an opaque pointer
-- for C code. Called by platform bridges after 'haskellRunMain'.
-- Reads the context from the registered 'MobileApp'.
-- Returns 'nullPtr' if the app is not registered or an exception occurs.
haskellCreateContext :: IO (Ptr ())
haskellCreateContext =
  catch
    (do app <- getMobileApp
        castStablePtrToPtr <$> newMobileContext (maContext app))
    (\exc -> do
      handleException (exc :: SomeException)
      pure nullPtr)

foreign export ccall haskellCreateContext :: IO (Ptr ())

-- | Render the UI tree. Calls 'maView' from the registered 'MobileApp'
-- to get the widget description, then issues ui_* calls through the
-- registered bridge callbacks. Catches exceptions and shows error widget.
haskellRenderUI :: Ptr () -> IO ()
haskellRenderUI _ctxPtr =
  withExceptionHandler renderView

foreign export ccall haskellRenderUI :: Ptr () -> IO ()

-- | Handle a UI event from native code. Dispatches the callback
-- identified by @callbackId@, then re-renders the UI.
haskellOnUIEvent :: Ptr () -> CInt -> IO ()
haskellOnUIEvent _ctxPtr callbackId =
  withExceptionHandler $ do
    dispatchEvent (appRenderState globalAppState) (fromIntegral callbackId)
    renderView

foreign export ccall haskellOnUIEvent :: Ptr () -> CInt -> IO ()

-- | Handle a text change event from native code. Dispatches the callback
-- identified by @callbackId@ with the new text value. Does NOT re-render
-- to avoid EditText cursor/flicker issues on Android.
haskellOnUITextChange :: Ptr () -> CInt -> CString -> IO ()
haskellOnUITextChange _ctxPtr callbackId cstr =
  withExceptionHandler $ do
    str <- peekCString cstr
    dispatchTextEvent (appRenderState globalAppState) (fromIntegral callbackId) (pack str)

foreign export ccall haskellOnUITextChange :: Ptr () -> CInt -> CString -> IO ()

-- | Handle a permission result from native code.  Dispatches to the
-- callback registered by 'requestPermission'.
haskellOnPermissionResult :: Ptr () -> CInt -> CInt -> IO ()
haskellOnPermissionResult _ctxPtr requestId statusCode =
  withExceptionHandler $
    dispatchPermissionResult (appPermissionState globalAppState) requestId statusCode

foreign export ccall haskellOnPermissionResult :: Ptr () -> CInt -> CInt -> IO ()
