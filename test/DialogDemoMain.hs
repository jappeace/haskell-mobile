{-# LANGUAGE OverloadedStrings #-}
-- | Mobile entry point for the dialog-demo test app.
--
-- Used by the emulator and simulator dialog integration tests.
-- Starts directly in dialog-demo mode so no runtime switching is needed.
module Main where

import Data.IORef (newIORef, readIORef, writeIORef)
import Data.Text (pack)
import Foreign.Ptr (Ptr)
import HaskellMobile
  ( MobileApp(..)
  , Action
  , DialogAction(..)
  , DialogConfig(..)
  , DialogState(..)
  , AppContext
  , startMobileApp
  , derefAppContext
  , platformLog
  , showDialog
  , loggingMobileContext
  , newActionState
  , runActionM
  , createAction
  )
import HaskellMobile.AppContext (AppContext(..))
import HaskellMobile.Widget (ButtonConfig(..), TextConfig(..), Widget(..))

main :: IO (Ptr AppContext)
main = do
  actionState <- newActionState
  -- IORef indirection: actions are created before the AppContext exists,
  -- but the real DialogState is only available after startMobileApp.
  dialogStateRef <- newIORef (Nothing :: Maybe DialogState)
  (onShowAlert, onShowConfirm) <- runActionM actionState $ do
    alert <- createAction $ do
      Just dialogState <- readIORef dialogStateRef
      showDialog dialogState
        DialogConfig
          { dcTitle   = "Alert Title"
          , dcMessage = "This is a test alert"
          , dcButton1 = "OK"
          , dcButton2 = Nothing
          , dcButton3 = Nothing
          }
        (\action -> platformLog ("Dialog alert result: " <> pack (show action)))
    confirm <- createAction $ do
      Just dialogState <- readIORef dialogStateRef
      showDialog dialogState
        DialogConfig
          { dcTitle   = "Confirm Title"
          , dcMessage = "Do you confirm?"
          , dcButton1 = "Yes"
          , dcButton2 = Just "No"
          , dcButton3 = Nothing
          }
        (\action -> platformLog ("Dialog confirm result: " <> pack (show action)))
    pure (alert, confirm)
  ctxPtr <- startMobileApp MobileApp
    { maContext     = loggingMobileContext
    , maView        = \_userState -> dialogDemoView onShowAlert onShowConfirm
    , maActionState = actionState
    }
  -- Populate the IORef now that the AppContext exists.
  appCtx <- derefAppContext ctxPtr
  writeIORef dialogStateRef (Just (acDialogState appCtx))
  platformLog "Dialog demo app registered"
  pure ctxPtr

-- | Builds a Column with a label, a "Show Alert" button, and a "Show Confirm" button.
dialogDemoView :: Action -> Action -> IO Widget
dialogDemoView onShowAlert onShowConfirm = pure $ Column
  [ Text TextConfig { tcLabel = "Dialog Demo", tcFontConfig = Nothing }
  , Button ButtonConfig
      { bcLabel      = "Show Alert"
      , bcAction     = onShowAlert
      , bcFontConfig = Nothing
      }
  , Button ButtonConfig
      { bcLabel      = "Show Confirm"
      , bcAction     = onShowConfirm
      , bcFontConfig = Nothing
      }
  ]
