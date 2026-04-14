{-# LANGUAGE OverloadedStrings #-}
-- | Minimal demo app that depends on the @async@ package.
--
-- Reproducer for issue #163: adding @async@ as a cross-compilation
-- dependency causes the Android app to OOM-kill during @.so@ loading
-- at runtime (~5.3 GB RSS before any Haskell code executes).
--
-- The app will never actually reach @main@ on Android — the process
-- is killed during @dlopen@.  The code is valid so it compiles and
-- links; the emulator test asserts that the crash happens.
module Main where

import Control.Concurrent.Async (async, wait)
import Foreign.Ptr (Ptr)
import Hatter (startMobileApp, platformLog, loggingMobileContext, MobileApp(..), newActionState)
import Hatter.AppContext (AppContext)
import Hatter.Widget (TextConfig(..), Widget(..))

main :: IO (Ptr AppContext)
main = do
  -- Trivial use of async to ensure it is linked in.
  handle <- async (pure "async loaded")
  result <- wait handle
  platformLog result
  actionState <- newActionState
  startMobileApp MobileApp
    { maContext     = loggingMobileContext
    , maView        = \_userState -> pure (Text TextConfig { tcLabel = "Async loaded", tcFontConfig = Nothing })
    , maActionState = actionState
    }
