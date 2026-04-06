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
import Data.Text (Text)
import HaskellMobile.Widget (InputType(..), Widget(..))
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

-- | Map an 'InputType' to the numeric value sent to the platform bridge.
inputTypeToDouble :: InputType -> Double
inputTypeToDouble InputText   = 0
inputTypeToDouble InputNumber = 1

-- | Render a single 'Widget' node, returning its native node ID.
renderNode :: RenderState -> Widget -> IO Int32
renderNode _rs (Text label) = do
  nodeId <- Bridge.createNode Bridge.NodeText
  Bridge.setStrProp nodeId Bridge.PropText label
  pure nodeId
renderNode rs (Button label action) = do
  nodeId <- Bridge.createNode Bridge.NodeButton
  Bridge.setStrProp nodeId Bridge.PropText label
  callbackId <- registerCallback rs action
  Bridge.setHandler nodeId Bridge.EventClick callbackId
  pure nodeId
renderNode rs (TextInput inputType hint value onChange) = do
  nodeId <- Bridge.createNode Bridge.NodeTextInput
  Bridge.setStrProp nodeId Bridge.PropText value
  Bridge.setStrProp nodeId Bridge.PropHint hint
  Bridge.setNumProp nodeId Bridge.PropInputType (inputTypeToDouble inputType)
  callbackId <- registerTextCallback rs onChange
  Bridge.setHandler nodeId Bridge.EventTextChange callbackId
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

-- | Render a list of children and add them to a parent container.
renderChildren :: RenderState -> Int32 -> [Widget] -> IO ()
renderChildren rs parentId children =
  mapM_ (\child -> do
    childId <- renderNode rs child
    Bridge.addChild parentId childId
  ) children

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
