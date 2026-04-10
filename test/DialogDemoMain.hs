{-# LANGUAGE OverloadedStrings #-}
-- | Mobile entry point for the dialog-demo test app.
--
-- Used by the emulator and simulator dialog integration tests.
-- Starts directly in dialog-demo mode so no runtime switching is needed.
module Main where

import Data.Text (pack)
import Foreign.Ptr (Ptr)
import HaskellMobile
  ( MobileApp(..)
  , UserState(..)
  , DialogAction(..)
  , DialogConfig(..)
  , AppContext
  , startMobileApp
  , platformLog
  , showDialog
  , loggingMobileContext
  )
import HaskellMobile.Widget (ButtonConfig(..), TextConfig(..), User, Widget(..))

main :: IO (Ptr AppContext)
main = do
  ctxPtr <- startMobileApp dialogDemoApp
  platformLog "Dialog demo app registered"
  pure ctxPtr

-- | Dialog demo: shows alert and confirm dialogs on button taps.
-- Used by integration tests to verify the dialog FFI bridge end-to-end.
dialogDemoApp :: MobileApp
dialogDemoApp = MobileApp
  { maContext = loggingMobileContext
  , maView    = dialogDemoView
  }

-- | Builds a Column with a label, a "Show Alert" button, and a "Show Confirm" button.
dialogDemoView :: UserState -> IO (Widget User)
dialogDemoView userState = pure $ Column
  [ Text TextConfig { tcLabel = "Dialog Demo", tcFontConfig = Nothing }
  , Button ButtonConfig
      { bcLabel = "Show Alert"
      , bcAction = showDialog (userDialogState userState)
          DialogConfig
            { dcTitle   = "Alert Title"
            , dcMessage = "This is a test alert"
            , dcButton1 = "OK"
            , dcButton2 = Nothing
            , dcButton3 = Nothing
            }
          (\action -> platformLog ("Dialog alert result: " <> pack (show action)))
      , bcFontConfig = Nothing
      }
  , Button ButtonConfig
      { bcLabel = "Show Confirm"
      , bcAction = showDialog (userDialogState userState)
          DialogConfig
            { dcTitle   = "Confirm Title"
            , dcMessage = "Do you confirm?"
            , dcButton1 = "Yes"
            , dcButton2 = Just "No"
            , dcButton3 = Nothing
            }
          (\action -> platformLog ("Dialog confirm result: " <> pack (show action)))
      , bcFontConfig = Nothing
      }
  ]
