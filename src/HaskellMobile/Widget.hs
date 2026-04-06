-- | Declarative UI widget ADT.
--
-- Pure data describing the UI tree. Rendering is handled by
-- "HaskellMobile.Render", which traverses this tree and issues
-- FFI calls to the platform bridge.
module HaskellMobile.Widget
  ( InputType(..)
  , Widget(..)
  )
where

import Data.Text (Text)

-- | The kind of on-screen keyboard to show for a 'TextInput'.
data InputType
  = InputText    -- ^ Default text keyboard.
  | InputNumber  -- ^ Numeric keyboard with decimal support.
  deriving (Show, Eq)

-- | A declarative description of a UI element.
data Widget
  = Text Text
    -- ^ A read-only text label.
  | Button Text (IO ())
    -- ^ A tappable button with a label and click handler.
  | TextInput InputType Text Text (Text -> IO ())
    -- ^ A text input field: input type, placeholder, current value, onChange handler.
    -- Follows a controlled-component pattern: Haskell owns the state.
  | Column [Widget]
    -- ^ A vertical container laying out children top-to-bottom.
  | Row [Widget]
    -- ^ A horizontal container laying out children left-to-right.
  | ScrollView [Widget]
    -- ^ A vertically scrollable container.
