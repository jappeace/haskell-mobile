-- | Declarative UI widget ADT.
--
-- Pure data describing the UI tree. Rendering is handled by
-- "HaskellMobile.Render", which traverses this tree and issues
-- FFI calls to the platform bridge.
module HaskellMobile.Widget
  ( Widget(..)
  )
where

import Data.Text (Text)

-- | A declarative description of a UI element.
data Widget
  = Text Text
    -- ^ A read-only text label.
  | Button Text (IO ())
    -- ^ A tappable button with a label and click handler.
  | Column [Widget]
    -- ^ A vertical container laying out children top-to-bottom.
  | Row [Widget]
    -- ^ A horizontal container laying out children left-to-right.
