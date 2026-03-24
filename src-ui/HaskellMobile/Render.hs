{-# LANGUAGE ImportQualifiedPost #-}
-- | Rendering engine that converts a 'Widget' tree into native UI
-- via the C bridge.
--
-- Uses a full clear-and-rebuild strategy on every render.
-- Maintains a callback registry so native button presses can be
-- dispatched back to Haskell 'IO' actions.
module HaskellMobile.Render
  ( RenderState(..)
  , newRenderState
  , renderWidget
  , dispatchEvent
  )
where

import Data.IORef (IORef, newIORef, readIORef, writeIORef, modifyIORef')
import Data.Int (Int32)
import Data.IntMap.Strict (IntMap)
import Data.IntMap.Strict qualified as IntMap
import HaskellMobile.Widget (Widget(..))
import HaskellMobile.UIBridge qualified as Bridge
import System.IO (hPutStrLn, stderr)

-- | Mutable state for the rendering engine.
-- Holds the callback registry and next callback ID counter.
data RenderState = RenderState
  { rsCallbacks :: IORef (IntMap (IO ()))
    -- ^ Map from callbackId -> IO action
  , rsNextId    :: IORef Int32
    -- ^ Next available callback ID
  }

-- | Create a fresh 'RenderState' with no registered callbacks.
newRenderState :: IO RenderState
newRenderState = do
  callbacks <- newIORef IntMap.empty
  nextId    <- newIORef 0
  pure RenderState
    { rsCallbacks = callbacks
    , rsNextId    = nextId
    }

-- | Register a callback and return its ID.
registerCallback :: RenderState -> IO () -> IO Int32
registerCallback rs action = do
  cid <- readIORef (rsNextId rs)
  modifyIORef' (rsCallbacks rs) (IntMap.insert (fromIntegral cid) action)
  writeIORef (rsNextId rs) (cid + 1)
  pure cid

-- | Reset the callback registry (called before each re-render).
resetCallbacks :: RenderState -> IO ()
resetCallbacks rs = do
  writeIORef (rsCallbacks rs) IntMap.empty
  writeIORef (rsNextId rs) 0

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
renderNode rs (Column children) = do
  nodeId <- Bridge.createNode Bridge.NodeColumn
  renderChildren rs nodeId children
  pure nodeId
renderNode rs (Row children) = do
  nodeId <- Bridge.createNode Bridge.NodeRow
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

-- | Dispatch a native event to the registered Haskell callback.
-- Logs an error to stderr if the callbackId is not found.
dispatchEvent :: RenderState -> Int32 -> IO ()
dispatchEvent rs callbackId = do
  callbacks <- readIORef (rsCallbacks rs)
  case IntMap.lookup (fromIntegral callbackId) callbacks of
    Just action -> action
    Nothing     -> hPutStrLn stderr $
      "dispatchEvent: unknown callback ID " ++ show callbackId
