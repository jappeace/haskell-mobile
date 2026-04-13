{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE OverloadedStrings #-}
-- | Entry point for consumer-side Template Haskell test.
--
-- Unlike THDemoMain (which imports TH from a dependency package),
-- this module uses a TH splice directly.  If this builds for
-- aarch64-android, TH works in consumer code compiled by mkAndroidLib.
module Main where

import Data.Text (pack)
import Foreign.Ptr (Ptr)
import Language.Haskell.TH.Syntax (lift)
import Hatter (startMobileApp, platformLog, loggingMobileContext, MobileApp(..), newActionState)
import Hatter.AppContext (AppContext)
import Hatter.Widget (TextConfig(..), Widget(..))

-- | Compile-time evaluated splice — forces -fexternal-interpreter in mkAndroidLib.
thMessage :: String
thMessage = $(lift ("TH in consumer code works!" :: String))

main :: IO (Ptr AppContext)
main = do
  platformLog (pack thMessage)
  actionState <- newActionState
  startMobileApp MobileApp
    { maContext     = loggingMobileContext
    , maView        = \_userState -> pure (Text TextConfig { tcLabel = "th-direct", tcFontConfig = Nothing })
    , maActionState = actionState
    }
