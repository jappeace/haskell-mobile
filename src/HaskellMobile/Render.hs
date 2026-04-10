{-# LANGUAGE ImportQualifiedPost #-}
-- | Rendering engine that converts a 'Widget' tree into native UI
-- via the C bridge.
--
-- Uses a full clear-and-rebuild strategy on every render.
-- Callbacks are stored in a shared 'ActionState' registry that is
-- never cleared during rendering — handles inside widget configs
-- reference stable entries in the registry.
module HaskellMobile.Render
  ( RenderState(..)
  , newRenderState
  , renderWidget
  , dispatchEvent
  , dispatchTextEvent
  )
where

import Data.Int (Int32)
import Data.Text (Text, pack)
import HaskellMobile.Action (Action(..), ActionState, OnChange(..), lookupAction, lookupTextAction)
import HaskellMobile.Widget (ButtonConfig(..), FontConfig(..), ImageConfig(..), ImageSource(..), InputType(..), ResourceName(..), ScaleType(..), TextAlignment(..), TextConfig(..), TextInputConfig(..), WebViewConfig(..), Widget(..), WidgetStyle(..), colorToHex)
import HaskellMobile.UIBridge qualified as Bridge
import System.IO (hPutStrLn, stderr)

-- | Mutable state for the rendering engine.
-- Holds a reference to the shared 'ActionState' callback registry.
data RenderState = RenderState
  { rsActionState :: ActionState
    -- ^ Shared callback registry (never cleared during rendering).
  }

-- | Create a fresh 'RenderState' wrapping the given 'ActionState'.
newRenderState :: ActionState -> IO RenderState
newRenderState actionState =
  pure RenderState
    { rsActionState = actionState
    }

-- | Map an 'InputType' to the numeric code sent to the platform bridge.
inputTypeToInt :: InputType -> Int32
inputTypeToInt InputText   = 0
inputTypeToInt InputNumber = 1

-- | Apply a 'FontConfig' to a rendered node if present.
applyFontConfig :: Int32 -> Maybe FontConfig -> IO ()
applyFontConfig nodeId (Just (FontConfig size)) =
  Bridge.setNumProp nodeId Bridge.PropFontSize size
applyFontConfig _nodeId Nothing = pure ()

-- | Render a single 'Widget' node, returning its native node ID.
renderNode :: Widget -> IO Int32
renderNode (Text config) = do
  nodeId <- Bridge.createNode Bridge.NodeText
  Bridge.setStrProp nodeId Bridge.PropText (tcLabel config)
  applyFontConfig nodeId (tcFontConfig config)
  pure nodeId
renderNode (Button config) = do
  nodeId <- Bridge.createNode Bridge.NodeButton
  Bridge.setStrProp nodeId Bridge.PropText (bcLabel config)
  Bridge.setHandler nodeId Bridge.EventClick (actionId (bcAction config))
  applyFontConfig nodeId (bcFontConfig config)
  pure nodeId
renderNode (TextInput config) = do
  nodeId <- Bridge.createNode Bridge.NodeTextInput
  Bridge.setStrProp nodeId Bridge.PropText (tiValue config)
  Bridge.setStrProp nodeId Bridge.PropHint (tiHint config)
  Bridge.setNumProp nodeId Bridge.PropInputType (fromIntegral (inputTypeToInt (tiInputType config)))
  Bridge.setHandler nodeId Bridge.EventTextChange (onChangeId (tiOnChange config))
  applyFontConfig nodeId (tiFontConfig config)
  pure nodeId
renderNode (Column children) = do
  nodeId <- Bridge.createNode Bridge.NodeColumn
  renderChildren nodeId children
  pure nodeId
renderNode (Row children) = do
  nodeId <- Bridge.createNode Bridge.NodeRow
  renderChildren nodeId children
  pure nodeId
renderNode (ScrollView children) = do
  nodeId <- Bridge.createNode Bridge.NodeScrollView
  renderChildren nodeId children
  pure nodeId
renderNode (Image config) = do
  nodeId <- Bridge.createNode Bridge.NodeImage
  case icSource config of
    ImageResource (ResourceName name) -> Bridge.setStrProp nodeId Bridge.PropImageResource name
    ImageData bytes                   -> Bridge.setImageData nodeId bytes
    ImageFile path                    -> Bridge.setStrProp nodeId Bridge.PropImageFile (pack path)
  Bridge.setNumProp nodeId Bridge.PropScaleType (scaleTypeToDouble (icScaleType config))
  pure nodeId
renderNode (WebView config) = do
  nodeId <- Bridge.createNode Bridge.NodeWebView
  Bridge.setStrProp nodeId Bridge.PropWebViewUrl (wvUrl config)
  case wvOnPageLoad config of
    Just action -> Bridge.setHandler nodeId Bridge.EventClick (actionId action)
    Nothing     -> pure ()
  pure nodeId
renderNode (Styled style child) = do
  nodeId <- renderNode child
  applyStyle nodeId style
  pure nodeId

-- | Render a list of children and add them to a parent container.
renderChildren :: Int32 -> [Widget] -> IO ()
renderChildren parentId children =
  mapM_ (\child -> do
    childId <- renderNode child
    Bridge.addChild parentId childId
  ) children

-- | Map a 'ScaleType' to the numeric code sent to the platform bridge.
scaleTypeToDouble :: ScaleType -> Double
scaleTypeToDouble ScaleFit  = 0
scaleTypeToDouble ScaleFill = 1
scaleTypeToDouble ScaleNone = 2

-- | Map a 'TextAlignment' to the numeric code sent to the platform bridge.
textAlignToDouble :: TextAlignment -> Double
textAlignToDouble AlignStart  = 0
textAlignToDouble AlignCenter = 1
textAlignToDouble AlignEnd    = 2

-- | Apply 'WidgetStyle' overrides to a rendered node by calling
-- 'Bridge.setNumProp' / 'Bridge.setStrProp' for each 'Just' field.
applyStyle :: Int32 -> WidgetStyle -> IO ()
applyStyle nodeId style = do
  case wsPadding style of
    Just padding -> Bridge.setNumProp nodeId Bridge.PropPadding padding
    Nothing      -> pure ()
  case wsTextAlign style of
    Just alignment -> Bridge.setNumProp nodeId Bridge.PropGravity (textAlignToDouble alignment)
    Nothing        -> pure ()
  case wsTextColor style of
    Just color -> Bridge.setStrProp nodeId Bridge.PropColor (colorToHex color)
    Nothing    -> pure ()
  case wsBackgroundColor style of
    Just color -> Bridge.setStrProp nodeId Bridge.PropBgColor (colorToHex color)
    Nothing    -> pure ()

-- | Full render: clear the screen, build the widget tree, and set
-- the root node.  Callback registries are /not/ cleared — handles
-- in the widget tree reference stable entries in the shared
-- 'ActionState'.
renderWidget :: RenderState -> Widget -> IO ()
renderWidget _rs widget = do
  Bridge.clear
  rootId <- renderNode widget
  Bridge.setRoot rootId

-- | Dispatch a native click event to the registered Haskell callback.
-- Logs an error to stderr if the callbackId is not found.
dispatchEvent :: RenderState -> Int32 -> IO ()
dispatchEvent rs callbackId = do
  maybeAction <- lookupAction (rsActionState rs) callbackId
  case maybeAction of
    Just action -> action
    Nothing     -> hPutStrLn stderr $
      "dispatchEvent: unknown callback ID " ++ show callbackId

-- | Dispatch a native text-change event to the registered Haskell callback.
-- Does NOT trigger a re-render (avoids EditText flicker on Android).
-- Logs an error to stderr if the callbackId is not found.
dispatchTextEvent :: RenderState -> Int32 -> Text -> IO ()
dispatchTextEvent rs callbackId newText = do
  maybeAction <- lookupTextAction (rsActionState rs) callbackId
  case maybeAction of
    Just action -> action newText
    Nothing     -> hPutStrLn stderr $
      "dispatchTextEvent: unknown callback ID " ++ show callbackId
