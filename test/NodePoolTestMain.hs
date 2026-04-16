{-# LANGUAGE OverloadedStrings #-}
-- | Mobile entry point for the node-pool stress-test app.
--
-- Renders 300 nodes (1 Column + 299 Text children) to exceed the
-- default MAX_NODES=256 limit.  Used by integration tests to verify
-- that configurable / dynamic node pools work end-to-end.
module Main where

import Data.Text (pack)
import Foreign.Ptr (Ptr)
import Hatter (MobileApp(..), UserState(..), startMobileApp, newActionState)
import Hatter.AppContext (AppContext)
import Hatter.Lifecycle (loggingMobileContext)
import Hatter.Widget (TextConfig(..), Widget(..), column)

-- | Render 300 nodes: 1 Column parent + 299 Text children.
nodePoolTestView :: UserState -> IO Widget
nodePoolTestView _userState = pure $ column $
  map (\itemNumber -> Text TextConfig
    { tcLabel = "Item " <> pack (show (itemNumber :: Int))
    , tcFontConfig = Nothing
    }) [1..299]

main :: IO (Ptr AppContext)
main = do
  actionState <- newActionState
  startMobileApp MobileApp
    { maContext     = loggingMobileContext
    , maView        = nodePoolTestView
    , maActionState = actionState
    }
