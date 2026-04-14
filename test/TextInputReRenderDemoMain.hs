{-# LANGUAGE OverloadedStrings #-}
-- | Mobile entry point for the text-input-rerender test app.
--
-- Reproduces jappeace/prrrrrrrrr#47: typing in a TextInput should
-- trigger a re-render so that a dependent Text widget updates.
-- On master (before the fix) the Text stays at its initial value
-- because haskellOnUITextChange did not call renderView.
module Main where

import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.Text (Text, pack, unpack)
import Foreign.Ptr (Ptr)
import Hatter
  ( startMobileApp, platformLog, loggingMobileContext
  , MobileApp(..), newActionState, runActionM, createOnChange, OnChange
  )
import Hatter.AppContext (AppContext)
import Hatter.Widget
  ( InputType(..), TextConfig(..), TextInputConfig(..), Widget(..)
  )

main :: IO (Ptr AppContext)
main = do
  platformLog "TextInputReRender demo app registered"
  actionState <- newActionState
  typedRef <- newIORef ("" :: Text)
  onChange <- runActionM actionState $
    createOnChange (\newText -> writeIORef typedRef newText)
  startMobileApp MobileApp
    { maContext     = loggingMobileContext
    , maView        = \_userState -> textInputReRenderView typedRef onChange
    , maActionState = actionState
    }

-- | A TextInput paired with a Text that mirrors the typed value.
-- The Text label should update on every keystroke if OnChange
-- triggers a re-render.
textInputReRenderView :: IORef Text -> OnChange -> IO Widget
textInputReRenderView typedRef onChange = do
  typed <- readIORef typedRef
  let displayLabel = "Typed: " <> typed
  platformLog ("view rebuilt: " <> displayLabel)
  pure $ Column
    [ TextInput TextInputConfig
        { tiInputType  = InputText
        , tiHint       = "type here"
        , tiValue      = typed
        , tiOnChange   = onChange
        , tiFontConfig = Nothing
        }
    , Text TextConfig
        { tcLabel      = displayLabel
        , tcFontConfig = Nothing
        }
    ]
