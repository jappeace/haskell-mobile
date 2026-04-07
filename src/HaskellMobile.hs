{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE OverloadedStrings #-}
module HaskellMobile
  ( MobileApp(..)
  , runMobileApp
  , getMobileApp
  -- FFI exports
  , haskellGreet
  , haskellCreateContext
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

import Data.Text (pack)
import Foreign.C.String (CString, newCString, peekCString)
import Foreign.C.Types (CInt(..))
import Foreign.Ptr (Ptr)
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
haskellCreateContext :: IO (Ptr ())
haskellCreateContext = do
  app <- getMobileApp
  castStablePtrToPtr <$> newMobileContext (maContext app)

foreign export ccall haskellCreateContext :: IO (Ptr ())

-- | Render the UI tree. Calls 'maView' from the registered 'MobileApp'
-- to get the widget description, then issues ui_* calls through the
-- registered bridge callbacks.
haskellRenderUI :: Ptr () -> IO ()
haskellRenderUI _ctxPtr = do
  app <- getMobileApp
  widget <- maView app
  renderWidget (appRenderState globalAppState) widget

foreign export ccall haskellRenderUI :: Ptr () -> IO ()

-- | Handle a UI event from native code. Dispatches the callback
-- identified by @callbackId@, then re-renders the UI.
haskellOnUIEvent :: Ptr () -> CInt -> IO ()
haskellOnUIEvent _ctxPtr callbackId = do
  dispatchEvent (appRenderState globalAppState) (fromIntegral callbackId)
  app <- getMobileApp
  widget <- maView app
  renderWidget (appRenderState globalAppState) widget

foreign export ccall haskellOnUIEvent :: Ptr () -> CInt -> IO ()

-- | Handle a text change event from native code. Dispatches the callback
-- identified by @callbackId@ with the new text value. Does NOT re-render
-- to avoid EditText cursor/flicker issues on Android.
haskellOnUITextChange :: Ptr () -> CInt -> CString -> IO ()
haskellOnUITextChange _ctxPtr callbackId cstr = do
  str <- peekCString cstr
  dispatchTextEvent (appRenderState globalAppState) (fromIntegral callbackId) (pack str)

foreign export ccall haskellOnUITextChange :: Ptr () -> CInt -> CString -> IO ()

-- | Handle a permission result from native code.  Dispatches to the
-- callback registered by 'requestPermission'.
haskellOnPermissionResult :: Ptr () -> CInt -> CInt -> IO ()
haskellOnPermissionResult _ctxPtr requestId statusCode =
  dispatchPermissionResult (appPermissionState globalAppState) requestId statusCode

foreign export ccall haskellOnPermissionResult :: Ptr () -> CInt -> CInt -> IO ()
