{-# LANGUAGE ImportQualifiedPost #-}
-- | Declarative UI widget ADT.
--
-- Pure data describing the UI tree. Rendering is handled by
-- "Hatter.Render", which traverses this tree and issues
-- FFI calls to the platform bridge.
--
-- Callback fields carry opaque 'Action' \/ 'OnChange' handles
-- (from "Hatter.Action") rather than raw @IO ()@ closures.
-- This lets 'Widget' derive 'Eq', enabling O(1) "skip if unchanged"
-- in the render diff.
module Hatter.Widget
  (
    Widget(..)
  -- ** configs
  , LayoutSettings(..)
  , WidgetKey(..)
  , LayoutItem(..)
  , WidgetStyle(..)
  , defaultStyle
  , ButtonConfig(..)
  , FontConfig(..)
  , ImageConfig(..)
  , ImageSource(..)
  , InputType(..)
  , MapViewConfig(..)
  , ResourceName(..)
  , ScaleType(..)
  , TextAlignment(..)
  , TextConfig(..)
  , TextInputConfig(..)
  , WebViewConfig(..)
  -- ** color
  , Color(..)
  , colorFromText
  , colorToHex
  -- ** animation
  , Easing(..)
  , AnimatedConfig(..)
  , normalizeAnimated
  , interpolateColor
  , lerpWord8
  -- ** key resolution
  , resolveKeyAtIndex
  -- ** smart constructors
  , button
  , column
  , item
  , keyedItem
  , row
  , scrollColumn
  , scrollRow
  , text
  )
where

import Data.ByteString (ByteString)
import Data.Char (digitToInt, isHexDigit, intToDigit)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word8)
import Hatter.Action (Action, OnChange)

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
  { tiInputType  :: InputType
    -- ^ Which on-screen keyboard to present.
  , tiHint       :: Text
    -- ^ Placeholder text shown when the field is empty.
  , tiValue      :: Text
    -- ^ Current text value (controlled by Haskell).
  , tiOnChange   :: OnChange
    -- ^ Handle for the callback fired when the user edits the field.
  , tiFontConfig :: Maybe FontConfig
    -- ^ Optional font override.
  , tiAutoFocus  :: Bool
    -- ^ Whether this input should receive focus when rendered.
    -- On Android, defers @requestFocus()@ via @View.post()@ to ensure the
    -- view is attached to the hierarchy first. On iOS, calls
    -- @becomeFirstResponder@. No-op on watchOS.
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
  , wsTranslateX      :: Maybe Double
    -- ^ Horizontal translation offset in platform-native units.
    -- Moves the widget without affecting sibling layout
    -- (Android: @translationX@, iOS: @CGAffineTransform@,
    -- watchOS: @.offset(x:y:)@).
  , wsTranslateY      :: Maybe Double
    -- ^ Vertical translation offset in platform-native units.
    -- Moves the widget without affecting sibling layout.
  , wsTouchPassthrough :: Maybe Bool
    -- ^ When 'True', the widget does not intercept touches, allowing
    -- sibling views underneath (in a 'Stack') to receive them.
    -- Android: @setClickable(false)@/@setFocusable(false)@.
    -- iOS: @userInteractionEnabled = NO@.
    -- watchOS: no-op (hit testing is automatic with ZStack).
  } deriving (Show, Eq)

-- | No style overrides — all fields are 'Nothing'.
defaultStyle :: WidgetStyle
defaultStyle = WidgetStyle
  { wsPadding          = Nothing
  , wsTextAlign        = Nothing
  , wsTextColor        = Nothing
  , wsBackgroundColor  = Nothing
  , wsTranslateX       = Nothing
  , wsTranslateY       = Nothing
  , wsTouchPassthrough = Nothing
  }

-- | Easing function for animations.
data Easing
  = Linear     -- ^ Constant speed.
  | EaseIn     -- ^ Slow start, fast end.
  | EaseOut    -- ^ Fast start, slow end.
  | EaseInOut  -- ^ Slow start and end, fast middle.
  deriving (Show, Eq)

-- | Configuration for an 'Animated' widget wrapper.
--
-- When 'Animated' wraps a container ('Column', 'Row'), the config is
-- distributed to each child:
--
-- @
-- Animated cfg (Column [a, b, c])  =  Column [Animated cfg a, Animated cfg b, Animated cfg c]
-- @
--
-- When two 'Animated' wrappers are nested, the __inner config wins__ — the
-- outer wrapper is stripped.  This lets you animate a whole container while
-- overriding individual children:
--
-- @
-- Animated (AnimatedConfig 500 EaseOut) $
--   Column
--     [ styledText   -- inherits 500ms EaseOut
--     , Animated (AnimatedConfig 100 EaseIn) fastWidget  -- keeps 100ms EaseIn
--     ]
-- @
--
-- Non-animatable children (containers with no visual properties of their
-- own) are recursively distributed until a leaf or 'Styled' node is
-- reached.
data AnimatedConfig = AnimatedConfig
  { anDuration :: Double
    -- ^ Animation duration in milliseconds.
  , anEasing   :: Easing
    -- ^ Easing function to apply.
  } deriving (Show, Eq)

-- | Linearly interpolate a single 'Word8' channel.
lerpWord8 :: Word8 -> Word8 -> Double -> Word8
lerpWord8 from to progress =
  round (fromIntegral from + (fromIntegral to - fromIntegral from) * progress :: Double)

-- | Interpolate between two colors by lerping each RGBA channel.
interpolateColor :: Color -> Color -> Double -> Color
interpolateColor (Color r1 g1 b1 a1) (Color r2 g2 b2 a2) progress = Color
  { colorRed   = lerpWord8 r1 r2 progress
  , colorGreen = lerpWord8 g1 g2 progress
  , colorBlue  = lerpWord8 b1 b2 progress
  , colorAlpha = lerpWord8 a1 a2 progress
  }

-- | Normalize an 'Animated' wrapper before rendering.
--
-- * Distributes 'Animated' over container children ('Column', 'Row').
-- * Collapses nested 'Animated' — inner config wins.
-- * All other widgets ('Styled', leaves) are returned unchanged;
--   the render engine wraps them in @RenderedAnimated@ for tween
--   interpolation.
normalizeAnimated :: AnimatedConfig -> Widget -> Widget
-- Inner Animated wins: strip the outer config.
normalizeAnimated _outerConfig (Animated innerConfig child) =
  Animated innerConfig (normalizeAnimated innerConfig child)
-- Distribute over containers: wrap each child's widget in Animated,
-- preserving the LayoutItem key.
normalizeAnimated config (Column settings) =
  Column settings { lsWidgets = map (wrapLayoutItemAnimated config) (lsWidgets settings) }
normalizeAnimated config (Row settings) =
  Row settings { lsWidgets = map (wrapLayoutItemAnimated config) (lsWidgets settings) }
normalizeAnimated config (Stack items) =
  Stack (map (wrapLayoutItemAnimated config) items)
-- Everything else (Styled, leaves): return unchanged.
-- The caller wraps the result in Animated for the render engine.
normalizeAnimated _config other = other

-- | Wrap a 'LayoutItem''s widget in 'Animated', preserving the key.
wrapLayoutItemAnimated :: AnimatedConfig -> LayoutItem -> LayoutItem
wrapLayoutItemAnimated config li = li { liWidget = Animated config (liWidget li) }

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

-- | Configuration for an embedded map view.
-- Uses native MapKit on iOS, placeholder on Android/watchOS.
data MapViewConfig = MapViewConfig
  { mvLatitude         :: Double
    -- ^ Center latitude.
  , mvLongitude        :: Double
    -- ^ Center longitude.
  , mvZoom             :: Double
    -- ^ Zoom level (1–20).
  , mvShowUserLocation :: Bool
    -- ^ Whether to show the user's current location.
  , mvOnRegionChange   :: Maybe OnChange
    -- ^ Optional callback fired when the user pans\/zooms.
    -- Receives @\"lat,lon,zoom\"@ text encoding the new center and zoom.
  } deriving (Show, Eq)

-- | An opaque key used to match children across renders.
-- Explicitly set by the user via 'keyedItem'.
newtype WidgetKey = WidgetKey { unWidgetKey :: Int }
  deriving (Show, Eq)

-- | A keyed container child.  The key is used by the diff algorithm
-- to match old and new children across renders, avoiding unnecessary
-- destruction and recreation of native views.
data LayoutItem = LayoutItem
  { liKey    :: Maybe WidgetKey
    -- ^ Explicit key, or 'Nothing' for auto-inference.
  , liWidget :: Widget
    -- ^ The child widget.
  } deriving (Show, Eq)

-- | Layout settings for container widgets ('Column', 'Row').
--
-- When 'lsScrollable' is 'True', the container renders as a native
-- scroll view (vertical for 'Column', horizontal for 'Row').
data LayoutSettings = LayoutSettings
  { lsWidgets    :: [LayoutItem]
    -- ^ Keyed child widgets inside the container.
  , lsScrollable :: Bool
    -- ^ Whether the container should be scrollable.
  } deriving (Show, Eq)

text :: Text -> Widget
text txt = Text $ TextConfig { tcLabel =  txt, tcFontConfig = Nothing }

button :: Text -> Action -> Widget
button txt action = Button $ ButtonConfig { bcLabel = txt, bcAction = action, bcFontConfig = Nothing }

-- | Wrap a widget in a 'LayoutItem' with no explicit key.
-- The diff algorithm will use the child's list index as its key.
item :: Widget -> LayoutItem
item widget = LayoutItem { liKey = Nothing, liWidget = widget }

-- | Wrap a widget in a 'LayoutItem' with an explicit key.
-- Use this when the inferred key would collide (e.g. two identical
-- text labels) or when you want stable identity across content changes.
keyedItem :: Int -> Widget -> LayoutItem
keyedItem keyValue widget = LayoutItem { liKey = Just (WidgetKey keyValue), liWidget = widget }

-- | Build a non-scrollable vertical container.
column :: [Widget] -> Widget
column widgets = Column LayoutSettings { lsWidgets = map item widgets, lsScrollable = False }

-- | Build a non-scrollable horizontal container.
row :: [Widget] -> Widget
row widgets = Row LayoutSettings { lsWidgets = map item widgets, lsScrollable = False }

-- | Build a scrollable vertical container (native scroll view).
scrollColumn :: [Widget] -> Widget
scrollColumn widgets = Column LayoutSettings { lsWidgets = map item widgets, lsScrollable = True }

-- | Build a scrollable horizontal container (native horizontal scroll view).
scrollRow :: [Widget] -> Widget
scrollRow widgets = Row LayoutSettings { lsWidgets = map item widgets, lsScrollable = True }

-- | A declarative description of a UI element.
--
--  This can do tree diffing (equality).
--  Therefore this doesn't contain any direct callbacks but actions instead.
--  Loosely binds to underlying IOS or Android components.
--
--  Tree diffing seems a bit excessive at first but it saves battery and
--  it also makes the animation mechanism possible.
data Widget
  = Text TextConfig
    -- ^ A read-only text label.
  | Button ButtonConfig
    -- ^ A tappable button with a label and click handler.
  | TextInput TextInputConfig
    -- ^ A text input field.
  | Column LayoutSettings
    -- ^ A vertical container laying out children top-to-bottom.
    -- When @'lsScrollable' = 'True'@, renders as a vertically scrollable container.
  | Row LayoutSettings
    -- ^ A horizontal container laying out children left-to-right.
    -- When @'lsScrollable' = 'True'@, renders as a horizontally scrollable container.
  | Stack [LayoutItem]
    -- ^ A z-order container: children overlap, first at bottom, last on top.
    -- Maps to FrameLayout (Android), plain UIView (iOS), ZStack (watchOS).
  | Image ImageConfig
    -- ^ An image widget displaying resource, file, or raw data.
  | WebView WebViewConfig
    -- ^ An embedded web view loading a URL.
  | MapView MapViewConfig
    -- ^ An embedded map view (native MapKit on iOS, placeholder elsewhere).
  | Styled WidgetStyle Widget
    -- ^ Apply visual style overrides to a child widget.
  | Animated AnimatedConfig Widget
    -- ^ Animate property changes on the child widget over a duration.
    -- When wrapping a container ('Column', 'Row'), the animation is
    -- distributed to each child.  Nested 'Animated' wrappers collapse:
    -- the innermost config wins.  See 'AnimatedConfig' for details.
  deriving (Show, Eq)

-- ---------------------------------------------------------------------------
-- Key resolution for child matching
-- ---------------------------------------------------------------------------

-- | Resolve the key for a 'LayoutItem' at a given list position:
-- use the explicit key if present, otherwise default to the list index.
resolveKeyAtIndex :: Int -> LayoutItem -> Int
resolveKeyAtIndex _index (LayoutItem (Just (WidgetKey keyValue)) _widget) = keyValue
resolveKeyAtIndex index (LayoutItem Nothing _widget) = index
