{-# LANGUAGE ImportQualifiedPost #-}
-- | Rendering engine that converts a 'Widget' tree into native UI
-- via the C bridge.
--
-- Uses a full clear-and-rebuild strategy on every render.
-- Maintains callback registries so native button presses and text
-- changes can be dispatched back to Haskell 'IO' actions.
module HaskellMobile.Render
  ( RenderState(..)
  , newRenderState
  , renderWidget
  , dispatchEvent
  , dispatchTextEvent
  )
where

import Data.IORef (IORef, newIORef, readIORef, writeIORef, modifyIORef')
import Data.Int (Int32)
import Data.IntMap.Strict (IntMap)
import Data.IntMap.Strict qualified as IntMap
import Data.Text (Text, pack)
import HaskellMobile.Widget (ButtonConfig(..), FontConfig(..), ImageConfig(..), ImageSource(..), InputType(..), ResourceName(..), ScaleType(..), TextAlignment(..), TextConfig(..), TextInputConfig(..), Widget(..), WidgetStyle(..), colorToHex)
import HaskellMobile.UIBridge qualified as Bridge
import System.IO (hPutStrLn, stderr)

-- | Mutable state for the rendering engine.
-- Holds the callback registries and next callback ID counter.
data RenderState = RenderState
  { rsCallbacks     :: IORef (IntMap (IO ()))
    -- ^ Map from callbackId -> IO action (for clicks)
  , rsTextCallbacks :: IORef (IntMap (Text -> IO ()))
    -- ^ Map from callbackId -> text change handler
  , rsNextId        :: IORef Int32
    -- ^ Next available callback ID
  }

-- | Create a fresh 'RenderState' with no registered callbacks.
newRenderState :: IO RenderState
newRenderState = do
  callbacks     <- newIORef IntMap.empty
  textCallbacks <- newIORef IntMap.empty
  nextId        <- newIORef 0
  pure RenderState
    { rsCallbacks     = callbacks
    , rsTextCallbacks = textCallbacks
    , rsNextId        = nextId
    }

-- | Register a click callback and return its ID.
registerCallback :: RenderState -> IO () -> IO Int32
registerCallback rs action = do
  cid <- readIORef (rsNextId rs)
  modifyIORef' (rsCallbacks rs) (IntMap.insert (fromIntegral cid) action)
  writeIORef (rsNextId rs) (cid + 1)
  pure cid

-- | Register a text-change callback and return its ID.
registerTextCallback :: RenderState -> (Text -> IO ()) -> IO Int32
registerTextCallback rs action = do
  cid <- readIORef (rsNextId rs)
  modifyIORef' (rsTextCallbacks rs) (IntMap.insert (fromIntegral cid) action)
  writeIORef (rsNextId rs) (cid + 1)
  pure cid

-- | Reset both callback registries (called before each re-render).
resetCallbacks :: RenderState -> IO ()
resetCallbacks rs = do
  writeIORef (rsCallbacks rs) IntMap.empty
  writeIORef (rsTextCallbacks rs) IntMap.empty
  writeIORef (rsNextId rs) 0

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
renderNode :: RenderState -> Widget -> IO Int32
renderNode _rs (Text config) = do
  nodeId <- Bridge.createNode Bridge.NodeText
  Bridge.setStrProp nodeId Bridge.PropText (tcLabel config)
  applyFontConfig nodeId (tcFontConfig config)
  pure nodeId
renderNode rs (Button config) = do
  nodeId <- Bridge.createNode Bridge.NodeButton
  Bridge.setStrProp nodeId Bridge.PropText (bcLabel config)
  callbackId <- registerCallback rs (bcAction config)
  Bridge.setHandler nodeId Bridge.EventClick callbackId
  applyFontConfig nodeId (bcFontConfig config)
  pure nodeId
renderNode rs (TextInput config) = do
  nodeId <- Bridge.createNode Bridge.NodeTextInput
  Bridge.setStrProp nodeId Bridge.PropText (tiValue config)
  Bridge.setStrProp nodeId Bridge.PropHint (tiHint config)
  Bridge.setNumProp nodeId Bridge.PropInputType (fromIntegral (inputTypeToInt (tiInputType config)))
  callbackId <- registerTextCallback rs (tiOnChange config)
  Bridge.setHandler nodeId Bridge.EventTextChange callbackId
  applyFontConfig nodeId (tiFontConfig config)
  pure nodeId
renderNode rs (Column children) = do
  nodeId <- Bridge.createNode Bridge.NodeColumn
  renderChildren rs nodeId children
  pure nodeId
renderNode rs (Row children) = do
  nodeId <- Bridge.createNode Bridge.NodeRow
  renderChildren rs nodeId children
  pure nodeId
renderNode rs (ScrollView children) = do
  nodeId <- Bridge.createNode Bridge.NodeScrollView
  renderChildren rs nodeId children
  pure nodeId
renderNode _rs (Image config) = do
  nodeId <- Bridge.createNode Bridge.NodeImage
  case icSource config of
    ImageResource (ResourceName name) -> Bridge.setStrProp nodeId Bridge.PropImageResource name
    ImageData bytes                   -> Bridge.setImageData nodeId bytes
    ImageFile path                    -> Bridge.setStrProp nodeId Bridge.PropImageFile (pack path)
  Bridge.setNumProp nodeId Bridge.PropScaleType (scaleTypeToDouble (icScaleType config))
  pure nodeId
renderNode rs (Styled style child) = do
  nodeId <- renderNode rs child
  applyStyle nodeId style
  pure nodeId

-- | Render a list of children and add them to a parent container.
renderChildren :: RenderState -> Int32 -> [Widget] -> IO ()
renderChildren rs parentId children =
  mapM_ (\child -> do
    childId <- renderNode rs child
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

-- | Full render: clear the screen, reset callbacks, build the widget
-- tree, and set the root node.
renderWidget :: RenderState -> Widget -> IO ()
renderWidget rs widget = do
  Bridge.clear
  resetCallbacks rs
  rootId <- renderNode rs widget
  Bridge.setRoot rootId

-- | Dispatch a native click event to the registered Haskell callback.
-- Logs an error to stderr if the callbackId is not found.
dispatchEvent :: RenderState -> Int32 -> IO ()
dispatchEvent rs callbackId = do
  callbacks <- readIORef (rsCallbacks rs)
  case IntMap.lookup (fromIntegral callbackId) callbacks of
    Just action -> action
    Nothing     -> hPutStrLn stderr $
      "dispatchEvent: unknown callback ID " ++ show callbackId

-- | Dispatch a native text-change event to the registered Haskell callback.
-- Does NOT trigger a re-render (avoids EditText flicker on Android).
-- Logs an error to stderr if the callbackId is not found.
dispatchTextEvent :: RenderState -> Int32 -> Text -> IO ()
dispatchTextEvent rs callbackId newText = do
  callbacks <- readIORef (rsTextCallbacks rs)
  case IntMap.lookup (fromIntegral callbackId) callbacks of
    Just action -> action newText
    Nothing     -> hPutStrLn stderr $
      "dispatchTextEvent: unknown callback ID " ++ show callbackId
