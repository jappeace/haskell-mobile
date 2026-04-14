{-# LANGUAGE OverloadedStrings #-}
-- | Minimal reproducer for DeadObjectException when ScrollView wraps
-- TextInput widgets on Android.
--
-- Mirrors the prrrrrrrrr enterPRView layout: ScrollView containing Text
-- labels, TextInput fields, and Buttons inside a Row.
module Main where

import Foreign.Ptr (Ptr)
import Hatter
  ( startMobileApp, platformLog, loggingMobileContext
  , MobileApp(..), newActionState, runActionM
  , createAction, createOnChange, Action, OnChange
  )
import Hatter.AppContext (AppContext)
import Hatter.Widget
  ( ButtonConfig(..), InputType(..), TextConfig(..)
  , TextInputConfig(..), Widget(..)
  )

main :: IO (Ptr AppContext)
main = do
  platformLog "ScrollTextInput demo app registered"
  actionState <- newActionState
  (save, back, onWeight, onNotes) <- runActionM actionState $ do
    saveAction <- createAction (platformLog "save pressed")
    backAction <- createAction (platformLog "back pressed")
    weightChange <- createOnChange (\_ -> pure ())
    notesChange <- createOnChange (\_ -> pure ())
    pure (saveAction, backAction, weightChange, notesChange)
  startMobileApp MobileApp
    { maContext     = loggingMobileContext
    , maView        = \_userState -> scrollTextInputView save back onWeight onNotes
    , maActionState = actionState
    }

-- | ScrollView containing TextInput widgets — reproduces the
-- prrrrrrrrr layout that triggers DeadObjectException.
scrollTextInputView :: Action -> Action -> OnChange -> OnChange -> IO Widget
scrollTextInputView save back onWeight onNotes = pure $ ScrollView
  [ Text TextConfig { tcLabel = "Enter data", tcFontConfig = Nothing }
  , TextInput TextInputConfig
      { tiInputType  = InputNumber
      , tiHint       = "Weight (kg)"
      , tiValue      = ""
      , tiOnChange   = onWeight
      , tiFontConfig = Nothing
      , tiAutoFocus  = False
      }
  , TextInput TextInputConfig
      { tiInputType  = InputText
      , tiHint       = "Notes"
      , tiValue      = ""
      , tiOnChange   = onNotes
      , tiFontConfig = Nothing
      , tiAutoFocus  = False
      }
  , Row
    [ Button ButtonConfig
        { bcLabel = "Save", bcAction = save, bcFontConfig = Nothing }
    , Button ButtonConfig
        { bcLabel = "Back", bcAction = back, bcFontConfig = Nothing }
    ]
  ]
