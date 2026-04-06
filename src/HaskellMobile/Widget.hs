-- | Declarative UI widget ADT.
--
-- Pure data describing the UI tree. Rendering is handled by
-- "HaskellMobile.Render", which traverses this tree and issues
-- FFI calls to the platform bridge.
module HaskellMobile.Widget
  ( InputType(..)
  , TextInputConfig(..)
  , Widget(..)
  , WidgetStyle(..)
  , defaultStyle
  )
where

import Data.Text (Text)

-- | The kind of on-screen keyboard to show for a 'TextInput'.
data InputType
  = InputText    -- ^ Default text keyboard.
  | InputNumber  -- ^ Numeric keyboard with decimal support.
  deriving (Show, Eq)

-- | Configuration for a text input field.
-- Follows a controlled-component pattern: Haskell owns the state.
data TextInputConfig = TextInputConfig
  { tiInputType :: InputType
    -- ^ Which on-screen keyboard to present.
  , tiHint      :: Text
    -- ^ Placeholder text shown when the field is empty.
  , tiValue     :: Text
    -- ^ Current text value (controlled by Haskell).
  , tiOnChange  :: Text -> IO ()
    -- ^ Callback fired when the user edits the field.
  }

-- | Visual style overrides for a widget node.
-- Each field is optional — 'Nothing' means "use the platform default".
data WidgetStyle = WidgetStyle
  { wsFontSize :: Maybe Double
    -- ^ Font size in platform-native units (sp on Android, pt on iOS).
  , wsPadding  :: Maybe Double
    -- ^ Uniform padding in platform-native units (px on Android, pt on iOS).
  } deriving (Show, Eq)

-- | No style overrides — all fields are 'Nothing'.
defaultStyle :: WidgetStyle
defaultStyle = WidgetStyle
  { wsFontSize = Nothing
  , wsPadding  = Nothing
  }

-- | A declarative description of a UI element.
data Widget
  = Text Text
    -- ^ A read-only text label.
  | Button Text (IO ())
    -- ^ A tappable button with a label and click handler.
  | TextInput TextInputConfig
    -- ^ A text input field.
  | Column [Widget]
    -- ^ A vertical container laying out children top-to-bottom.
  | Row [Widget]
    -- ^ A horizontal container laying out children left-to-right.
  | ScrollView [Widget]
    -- ^ A vertically scrollable container.
  | Styled WidgetStyle Widget
    -- ^ Apply visual style overrides to a child widget.
