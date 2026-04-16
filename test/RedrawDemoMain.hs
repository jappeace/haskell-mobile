{-# LANGUAGE OverloadedStrings #-}
-- | Self-contained redraw demo app.
--
-- Proves that background threads can trigger UI re-renders via
-- 'request_redraw'.  A C-level background thread (pthread) increments
-- a counter every 3 seconds and calls request_redraw; the Haskell view
-- reads the counter via FFI and logs each rebuild.
--
-- We use a C pthread rather than Haskell forkIO+threadDelay because
-- the non-threaded RTS on Android cannot schedule green threads between
-- JNI callbacks — threadDelay would block forever.
module Main where

import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.Text (pack)
import Foreign.C.Types (CInt(..))
import Foreign.Ptr (Ptr)
import Hatter
  ( MobileApp(..)
  , UserState(..)
  , startMobileApp
  , newActionState
  , loggingMobileContext
  , platformLog
  )
import Hatter.AppContext (AppContext)
import Hatter.Widget (TextConfig(..), Widget(..), column)
import Control.Monad (when)

-- | FFI: start a C-level background timer that calls request_redraw()
-- and platform_log("Background tick: N") every @interval_secs@ seconds,
-- for @count@ iterations.  Uses the context stored by redraw_store_ctx().
foreign import ccall "start_periodic_redraw"
  c_startPeriodicRedraw :: CInt -> CInt -> IO ()

-- | FFI: read the counter incremented by the C periodic timer thread.
foreign import ccall "get_periodic_counter"
  c_getPeriodicCounter :: IO CInt

main :: IO (Ptr AppContext)
main = do
  platformLog "Redraw demo registered"
  actionState <- newActionState
  -- Track whether the C timer has been started
  startedRef <- newIORef False
  startMobileApp MobileApp
    { maContext     = loggingMobileContext
    , maView        = redrawView startedRef
    , maActionState = actionState
    }

-- | View function: kicks off C-level background timer on first render,
-- reads the C counter, and logs each rebuild.
redrawView :: IORef Bool -> UserState -> IO Widget
redrawView startedRef _userState = do
  started <- readIORef startedRef
  when (not started) $ do
    writeIORef startedRef True
    -- Start C-level timer: 3 ticks, 3 seconds apart.
    -- The context was stored by redraw_store_ctx() in renderView.
    c_startPeriodicRedraw 3 3
  count <- fromIntegral <$> c_getPeriodicCounter
  platformLog ("view rebuilt: count=" <> pack (show (count :: Int)))
  pure $ column [Text TextConfig
    { tcLabel = "Count: " <> pack (show count)
    , tcFontConfig = Nothing
    }]
