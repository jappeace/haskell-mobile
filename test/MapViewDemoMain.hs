{-# LANGUAGE OverloadedStrings #-}
-- | Mobile entry point for the mapview-demo test app.
--
-- Used by the emulator and simulator MapView integration tests.
-- Renders a MapView centered on Amsterdam with a region-change callback.
module Main where

import Data.Text (pack)
import Foreign.Ptr (Ptr)
import Hatter
  ( MobileApp(..)
  , UserState
  , OnChange
  , startMobileApp
  , platformLog
  , loggingMobileContext
  , newActionState
  , runActionM
  , createOnChange
  )
import Hatter.AppContext (AppContext)
import Hatter.Widget
  ( MapViewConfig(..)
  , TextConfig(..)
  , Widget(..)
  , column
  )

main :: IO (Ptr AppContext)
main = do
  platformLog "MapView demo app registered"
  actionState <- newActionState
  onRegionChange <- runActionM actionState $
    createOnChange (\newRegion ->
      platformLog ("MapView region changed: " <> newRegion))
  startMobileApp MobileApp
    { maContext     = loggingMobileContext
    , maView        = mapViewDemoView onRegionChange
    , maActionState = actionState
    }

-- | Builds a Column with a label and a MapView centered on Amsterdam.
mapViewDemoView :: OnChange -> UserState -> IO Widget
mapViewDemoView onRegionChange _userState =
  pure $ column
    [ Text TextConfig { tcLabel = "MapView Demo", tcFontConfig = Nothing }
    , MapView MapViewConfig
        { mvLatitude         = 52.3676
        , mvLongitude        = 4.9041
        , mvZoom             = 12.0
        , mvShowUserLocation = False
        , mvOnRegionChange   = Just onRegionChange
        }
    ]
