{-# LANGUAGE ImportQualifiedPost #-}
-- | Declarative UI widget ADT.
--
-- Pure data describing the UI tree. Rendering is handled by
-- "HaskellMobile.Render", which traverses this tree and issues
-- FFI calls to the platform bridge.
--
-- Callback fields carry opaque 'Action' \/ 'OnChange' handles
-- (from "HaskellMobile.Action") rather than raw @IO ()@ closures.
-- This lets 'Widget' derive 'Eq', enabling O(1) "skip if unchanged"
-- in the render diff.
module HaskellMobile.Widget
  ( FontConfig(..)
  , TextConfig(..)
  , ButtonConfig(..)
  , InputType(..)
  , TextInputConfig(..)
  , ScaleType(..)
  , ResourceName(..)
  , ImageSource(..)
  , ImageConfig(..)
  , WebViewConfig(..)
  , Widget(..)
  , WidgetStyle(..)
  , TextAlignment(..)
  , Color(..)
  , colorFromText
  , colorToHex
  , defaultStyle
  )
where

import Data.ByteString (ByteString)
import Data.Char (digitToInt, isHexDigit, intToDigit)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word8)
import HaskellMobile.Action (Action, OnChange)

-- | Font configuration for text-bearing widgets.
-- Only 'Text', 'Button', and 'TextInput' can carry a 'FontConfig'.
newtype FontConfig = FontConfig
  { fontSize :: Double
    -- ^ Font size in platform-native units (sp on Android, pt on iOS).
  } deriving (Show, Eq)

-- | Configuration for a read-only text label.
data TextConfig = TextConfig
  { tcLabel      :: Text
    -- ^ The text content to display.
  , tcFontConfig :: Maybe FontConfig
    -- ^ Optional font override.
  } deriving (Show, Eq)

-- | Configuration for a tappable button.
data ButtonConfig = ButtonConfig
  { bcLabel      :: Text
    -- ^ The button's label text.
  , bcAction     :: Action
    -- ^ Handle for the callback fired when the button is tapped.
  , bcFontConfig :: Maybe FontConfig
    -- ^ Optional font override.
  } deriving (Show, Eq)

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
  , tiOnChange  :: OnChange
    -- ^ Handle for the callback fired when the user edits the field.
  , tiFontConfig :: Maybe FontConfig
    -- ^ Optional font override.
  } deriving (Show, Eq)

-- | Horizontal text alignment for text-bearing widgets.
data TextAlignment
  = AlignStart   -- ^ Left-aligned (LTR) or right-aligned (RTL).
  | AlignCenter  -- ^ Centered horizontally.
  | AlignEnd     -- ^ Right-aligned (LTR) or left-aligned (RTL).
  deriving (Show, Eq)

-- | An RGBA color with 8-bit channels.
data Color = Color
  { colorRed   :: Word8
  , colorGreen :: Word8
  , colorBlue  :: Word8
  , colorAlpha :: Word8
  } deriving (Show, Eq)

-- | Parse a hex color string: @"#RGB"@, @"#RRGGBB"@, or @"#AARRGGBB"@.
-- Returns 'Nothing' on invalid input.
colorFromText :: Text -> Maybe Color
colorFromText raw = do
  ('#', digits) <- Text.uncons raw
  let hex = Text.unpack digits
  if all isHexDigit hex
    then case hex of
      [r1, g1, b1] ->
        let expand ch = let val = digitToInt ch in fromIntegral (val * 16 + val)
        in Just (Color (expand r1) (expand g1) (expand b1) 255)
      [r1, r2, g1, g2, b1, b2] ->
        Just (Color (hexByte r1 r2) (hexByte g1 g2) (hexByte b1 b2) 255)
      [a1, a2, r1, r2, g1, g2, b1, b2] ->
        Just (Color (hexByte r1 r2) (hexByte g1 g2) (hexByte b1 b2) (hexByte a1 a2))
      _ -> Nothing
    else Nothing

-- | Convert two hex characters to a Word8.
hexByte :: Char -> Char -> Word8
hexByte high low = fromIntegral (digitToInt high * 16 + digitToInt low)

-- | Convert a 'Color' to a hex string in @"#AARRGGBB"@ format for the C bridge.
colorToHex :: Color -> Text
colorToHex (Color r g b a) = Text.pack ('#' : toHexByte a ++ toHexByte r ++ toHexByte g ++ toHexByte b)
  where
    toHexByte :: Word8 -> String
    toHexByte byte = [intToDigit (fromIntegral byte `div` 16), intToDigit (fromIntegral byte `mod` 16)]

-- | Visual style overrides for a widget node.
-- Font size is not here — it belongs in the config records of
-- text-bearing widgets ('TextConfig', 'ButtonConfig', 'TextInputConfig').
data WidgetStyle = WidgetStyle
  { wsPadding         :: Maybe Double
    -- ^ Uniform padding in platform-native units (px on Android, pt on iOS).
  , wsTextAlign       :: Maybe TextAlignment
    -- ^ Horizontal text alignment override.
  , wsTextColor       :: Maybe Color
    -- ^ Text color.
  , wsBackgroundColor :: Maybe Color
    -- ^ Background color.
  } deriving (Show, Eq)

-- | No style overrides — all fields are 'Nothing'.
defaultStyle :: WidgetStyle
defaultStyle = WidgetStyle
  { wsPadding         = Nothing
  , wsTextAlign       = Nothing
  , wsTextColor       = Nothing
  , wsBackgroundColor = Nothing
  }

-- | How an image should be scaled within its bounds.
data ScaleType
  = ScaleFit   -- ^ Scale to fit within bounds, preserving aspect ratio.
  | ScaleFill  -- ^ Scale to fill bounds, preserving aspect ratio (may crop).
  | ScaleNone  -- ^ No scaling; display at native resolution.
  deriving (Show, Eq)

-- | A platform resource name (e.g. @"ic_launcher"@, @"logo"@).
-- Wraps a 'Text' value that identifies a drawable\/image resource
-- bundled with the app. No compile-time guarantee that the resource
-- exists — a missing resource shows \"Image not found\" placeholder text
-- on iOS\/watchOS and an empty view on Android (with an error log).
newtype ResourceName = ResourceName { unResourceName :: Text }
  deriving (Show, Eq)

-- | Source of image data for an 'Image' widget.
data ImageSource
  = ImageResource ResourceName  -- ^ Platform resource by name.
  | ImageData ByteString        -- ^ Raw image bytes (PNG/JPEG).
  | ImageFile FilePath          -- ^ Absolute file path to an image on disk.
  deriving (Show, Eq)

-- | Configuration for an image widget.
data ImageConfig = ImageConfig
  { icSource    :: ImageSource
    -- ^ Where the image data comes from.
  , icScaleType :: ScaleType
    -- ^ How the image is scaled.
  } deriving (Show, Eq)

-- | Configuration for an embedded web view.
data WebViewConfig = WebViewConfig
  { wvUrl        :: Text
    -- ^ URL to load in the web view.
  , wvOnPageLoad :: Maybe Action
    -- ^ Optional handle for a callback fired when a page finishes loading.
  } deriving (Show, Eq)

-- | A declarative description of a UI element.
data Widget
  = Text TextConfig
    -- ^ A read-only text label.
  | Button ButtonConfig
    -- ^ A tappable button with a label and click handler.
  | TextInput TextInputConfig
    -- ^ A text input field.
  | Column [Widget]
    -- ^ A vertical container laying out children top-to-bottom.
  | Row [Widget]
    -- ^ A horizontal container laying out children left-to-right.
  | ScrollView [Widget]
    -- ^ A vertically scrollable container.
  | Image ImageConfig
    -- ^ An image widget displaying resource, file, or raw data.
  | WebView WebViewConfig
    -- ^ An embedded web view loading a URL.
  | Styled WidgetStyle Widget
    -- ^ Apply visual style overrides to a child widget.
  deriving (Show, Eq)
