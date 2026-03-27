{-# LANGUAGE ForeignFunctionInterface #-}
module HaskellMobile
  ( main
  , haskellInit
  , haskellGreet
  , haskellCreateContext
  , appContext
  , appView
  , LifecycleEvent(..)
  , MobileContext(..)
  , defaultMobileContext
  , loggingMobileContext
  , platformLog
  , newMobileContext
  , freeMobileContext
  )
where

import Foreign.C.String (CString, newCString, peekCString)
import Foreign.C.Types (CInt(..))
import Foreign.Ptr (Ptr)
import Foreign.StablePtr (castStablePtrToPtr)
import HaskellMobile.App (appContext, appView)
import HaskellMobile.Lifecycle
  ( LifecycleEvent(..)
  , MobileContext(..)
  , defaultMobileContext
  , loggingMobileContext
  , platformLog
  , newMobileContext
  , freeMobileContext
  )
import Data.Text (pack)
import HaskellMobile.Render (RenderState, newRenderState, renderWidget, dispatchEvent, dispatchTextEvent)
import System.IO.Unsafe (unsafePerformIO)

-- | Global render state, shared across all render/event cycles.
-- Safe because all UI calls happen on the main thread.
globalRenderState :: RenderState
globalRenderState = unsafePerformIO newRenderState
{-# NOINLINE globalRenderState #-}

main :: IO ()
main = putStrLn "hello, world flaky"

-- | Placeholder for RTS initialization, called from JNI_OnLoad
haskellInit :: IO ()
haskellInit = putStrLn "Haskell RTS initialized"

foreign export ccall haskellInit :: IO ()

-- | Takes a name as CString, returns "Hello from Haskell, <name>!" as CString.
-- Caller is responsible for freeing the returned CString.
haskellGreet :: CString -> IO CString
haskellGreet cname = do
  name <- peekCString cname
  newCString ("Hello from Haskell, " ++ name ++ "!")

foreign export ccall haskellGreet :: CString -> IO CString

-- | Create a default 'MobileContext' and return it as an opaque pointer
-- for C code. Called by platform bridges after 'haskellInit'.
haskellCreateContext :: IO (Ptr ())
haskellCreateContext = castStablePtrToPtr <$> newMobileContext appContext

foreign export ccall haskellCreateContext :: IO (Ptr ())

-- | Render the UI tree. Calls 'appView' to get the widget description,
-- then issues ui_* calls through the registered bridge callbacks.
-- The @ctx@ pointer is accepted for API consistency but not used for rendering.
haskellRenderUI :: Ptr () -> IO ()
haskellRenderUI _ctxPtr = do
  widget <- appView
  renderWidget globalRenderState widget

foreign export ccall haskellRenderUI :: Ptr () -> IO ()

-- | Handle a UI event from native code. Dispatches the callback
-- identified by @callbackId@, then re-renders the UI.
haskellOnUIEvent :: Ptr () -> CInt -> IO ()
haskellOnUIEvent _ctxPtr callbackId = do
  dispatchEvent globalRenderState (fromIntegral callbackId)
  widget <- appView
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
