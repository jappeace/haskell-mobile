{-# LANGUAGE CPP #-}
{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE OverloadedStrings #-}
module HaskellMobile
  ( MobileApp(..)
  , runMobileApp
  , getMobileApp
  -- FFI exports
  , haskellInit
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
  )
where

import Data.IORef (IORef, newIORef, readIORef, writeIORef)
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
import HaskellMobile.Render (RenderState, newRenderState, renderWidget, dispatchEvent, dispatchTextEvent)
import HaskellMobile.Widget (Widget)
import System.IO.Unsafe (unsafePerformIO)

#ifdef HASKELL_MOBILE_ANDROID
import HaskellMobile.App (mobileApp)
#endif

-- | Application definition record. Downstream apps create one of these
-- and register it via 'runMobileApp'.
data MobileApp = MobileApp
  { maContext :: MobileContext
  , maView    :: IO Widget
  }

-- | Global storage for the registered app. Filled by 'runMobileApp'.
globalMobileApp :: IORef (Maybe MobileApp)
globalMobileApp = unsafePerformIO (newIORef Nothing)
{-# NOINLINE globalMobileApp #-}

-- | Register the mobile app. Must be called before any FFI entry point.
-- Desktop apps call this from 'main'. Android builds call it from 'haskellInit'.
runMobileApp :: MobileApp -> IO ()
runMobileApp = writeIORef globalMobileApp . Just

-- | Read the registered app. Errors if 'runMobileApp' was not called.
getMobileApp :: IO MobileApp
getMobileApp = do
  mApp <- readIORef globalMobileApp
  case mApp of
    Just app -> pure app
    Nothing  -> error "haskell-mobile: runMobileApp was not called before FFI entry"

-- | Global render state, shared across all render/event cycles.
-- Safe because all UI calls happen on the main thread.
globalRenderState :: RenderState
globalRenderState = unsafePerformIO newRenderState
{-# NOINLINE globalRenderState #-}

-- | Called from JNI_OnLoad on Android.
-- On Android builds (CPP flag HASKELL_MOBILE_ANDROID), also registers
-- the downstream app via 'runMobileApp'.
haskellInit :: IO ()
haskellInit = do
  platformLog "Haskell RTS initialized"
#ifdef HASKELL_MOBILE_ANDROID
  runMobileApp mobileApp
#endif

foreign export ccall haskellInit :: IO ()

-- | Takes a name as CString, returns "Hello from Haskell, <name>!" as CString.
-- Caller is responsible for freeing the returned CString.
haskellGreet :: CString -> IO CString
haskellGreet cname = do
  name <- peekCString cname
  newCString ("Hello from Haskell, " ++ name ++ "!")

foreign export ccall haskellGreet :: CString -> IO CString

-- | Create a 'MobileContext' and return it as an opaque pointer
-- for C code. Called by platform bridges after 'haskellInit'.
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
  renderWidget globalRenderState widget

foreign export ccall haskellRenderUI :: Ptr () -> IO ()

-- | Handle a UI event from native code. Dispatches the callback
-- identified by @callbackId@, then re-renders the UI.
haskellOnUIEvent :: Ptr () -> CInt -> IO ()
haskellOnUIEvent _ctxPtr callbackId = do
  dispatchEvent globalRenderState (fromIntegral callbackId)
  app <- getMobileApp
  widget <- maView app
  renderWidget globalRenderState widget

foreign export ccall haskellOnUIEvent :: Ptr () -> CInt -> IO ()

-- | Handle a text change event from native code. Dispatches the callback
-- identified by @callbackId@ with the new text value. Does NOT re-render
-- to avoid EditText cursor/flicker issues on Android.
haskellOnUITextChange :: Ptr () -> CInt -> CString -> IO ()
haskellOnUITextChange _ctxPtr callbackId cstr = do
  str <- peekCString cstr
  dispatchTextEvent globalRenderState (fromIntegral callbackId) (pack str)

foreign export ccall haskellOnUITextChange :: Ptr () -> CInt -> CString -> IO ()
