{-# LANGUAGE ImportQualifiedPost #-}
-- | Rendering engine that converts a 'Widget' tree into native UI
-- via the C bridge.
--
-- Uses an incremental diff strategy: on each render, the new widget
-- tree is compared (via 'toUnit') against the previously rendered
-- tree. Only changed subtrees are destroyed and recreated; unchanged
-- nodes keep their native views and callback IDs.
module HaskellMobile.Render
  ( RenderState(..)
  , RenderedNode(..)
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
import HaskellMobile.Widget (ButtonConfig(..), FontConfig(..), ImageConfig(..), ImageSource(..), InputType(..), ResourceName(..), ScaleType(..), TextAlignment(..), TextConfig(..), TextInputConfig(..), User, WebViewConfig(..), Widget(..), WidgetStyle(..), colorToHex, toUnit)
import HaskellMobile.UIBridge qualified as Bridge
import System.IO (hPutStrLn, stderr)

-- ---------------------------------------------------------------------------
-- Rendered tree: retained structure for incremental diffing
-- ---------------------------------------------------------------------------

-- | A snapshot of a rendered widget, retaining the unit-stripped widget
-- (for equality comparison), native node IDs, and callback IDs.
data RenderedNode
  = RenderedLeaf
      (Widget ())    -- ^ Unit-stripped widget for equality comparison.
      Int32          -- ^ Native node ID from the platform bridge.
      (Maybe Int32)  -- ^ Callback ID if this leaf has a handler.
  | RenderedContainer
      (Widget ())    -- ^ Unit-stripped widget.
      Int32          -- ^ Native node ID.
      [RenderedNode] -- ^ Rendered children.
  | RenderedStyled
      (Widget ())    -- ^ Unit-stripped widget.
      WidgetStyle    -- ^ Applied style (for change detection).
      RenderedNode   -- ^ Child (Styled doesn't own a native node).

-- | Get the native node ID for a rendered node.
-- 'RenderedStyled' follows through to its child's node ID.
renderedNodeId :: RenderedNode -> Int32
renderedNodeId (RenderedLeaf _ nodeId _)      = nodeId
renderedNodeId (RenderedContainer _ nodeId _)  = nodeId
renderedNodeId (RenderedStyled _ _ child)      = renderedNodeId child

-- | Get the unit-stripped widget for a rendered node.
renderedUnitWidget :: RenderedNode -> Widget ()
renderedUnitWidget (RenderedLeaf unitW _ _)     = unitW
renderedUnitWidget (RenderedContainer unitW _ _) = unitW
renderedUnitWidget (RenderedStyled unitW _ _)    = unitW

-- ---------------------------------------------------------------------------
-- Render state
-- ---------------------------------------------------------------------------

-- | Mutable state for the rendering engine.
-- Holds the callback registries, next callback ID counter, and the
-- previously rendered tree for incremental diffing.
data RenderState = RenderState
  { rsCallbacks     :: IORef (IntMap (IO ()))
    -- ^ Map from callbackId -> IO action (for clicks).
  , rsTextCallbacks :: IORef (IntMap (Text -> IO ()))
    -- ^ Map from callbackId -> text change handler.
  , rsNextId        :: IORef Int32
    -- ^ Next available callback ID (monotonically increasing, never reset).
  , rsRenderedTree  :: IORef (Maybe RenderedNode)
    -- ^ The previously rendered tree, or 'Nothing' for the first render.
  }

-- | Create a fresh 'RenderState' with no registered callbacks.
newRenderState :: IO RenderState
newRenderState = do
  callbacks     <- newIORef IntMap.empty
  textCallbacks <- newIORef IntMap.empty
  nextId        <- newIORef 0
  renderedTree  <- newIORef Nothing
  pure RenderState
    { rsCallbacks     = callbacks
    , rsTextCallbacks = textCallbacks
    , rsNextId        = nextId
    , rsRenderedTree  = renderedTree
    }

-- ---------------------------------------------------------------------------
-- Callback registration
-- ---------------------------------------------------------------------------

-- | Register a click callback and return its fresh ID.
registerCallback :: RenderState -> IO () -> IO Int32
registerCallback rs action = do
  cid <- readIORef (rsNextId rs)
  modifyIORef' (rsCallbacks rs) (IntMap.insert (fromIntegral cid) action)
  writeIORef (rsNextId rs) (cid + 1)
  pure cid

-- | Register a text-change callback and return its fresh ID.
registerTextCallback :: RenderState -> (Text -> IO ()) -> IO Int32
registerTextCallback rs action = do
  cid <- readIORef (rsNextId rs)
  modifyIORef' (rsTextCallbacks rs) (IntMap.insert (fromIntegral cid) action)
  writeIORef (rsNextId rs) (cid + 1)
  pure cid

-- | Re-register a click callback at an existing ID.
-- Used for reused nodes: native view keeps the old callback ID tag,
-- but the Haskell closure is updated to the new action.
registerCallbackAt :: RenderState -> Int32 -> IO () -> IO ()
registerCallbackAt rs callbackId action =
  modifyIORef' (rsCallbacks rs) (IntMap.insert (fromIntegral callbackId) action)

-- | Re-register a text-change callback at an existing ID.
registerTextCallbackAt :: RenderState -> Int32 -> (Text -> IO ()) -> IO ()
registerTextCallbackAt rs callbackId action =
  modifyIORef' (rsTextCallbacks rs) (IntMap.insert (fromIntegral callbackId) action)

-- | Clear callback registries for a fresh render pass.
-- Does NOT reset 'rsNextId' — IDs grow monotonically so reused nodes
-- keep valid tags.
clearCallbackMaps :: RenderState -> IO ()
clearCallbackMaps rs = do
  writeIORef (rsCallbacks rs) IntMap.empty
  writeIORef (rsTextCallbacks rs) IntMap.empty

-- ---------------------------------------------------------------------------
-- Bridge helpers
-- ---------------------------------------------------------------------------

-- | Map an 'InputType' to the numeric code sent to the platform bridge.
inputTypeToInt :: InputType -> Int32
inputTypeToInt InputText   = 0
inputTypeToInt InputNumber = 1

-- | Apply a 'FontConfig' to a rendered node if present.
applyFontConfig :: Int32 -> Maybe FontConfig -> IO ()
applyFontConfig nodeId (Just (FontConfig size)) =
  Bridge.setNumProp nodeId Bridge.PropFontSize size
applyFontConfig _nodeId Nothing = pure ()

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

-- ---------------------------------------------------------------------------
-- Creating rendered nodes from scratch
-- ---------------------------------------------------------------------------

-- | Create a native node from a 'Widget', returning a 'RenderedNode'
-- snapshot. Used for fresh creation (no old node to diff against).
createRenderedNode :: RenderState -> Widget User -> IO RenderedNode
createRenderedNode _rs (Text config) = do
  nodeId <- Bridge.createNode Bridge.NodeText
  Bridge.setStrProp nodeId Bridge.PropText (tcLabel config)
  applyFontConfig nodeId (tcFontConfig config)
  pure (RenderedLeaf (toUnit (Text config)) nodeId Nothing)
createRenderedNode rs (Button config) = do
  nodeId <- Bridge.createNode Bridge.NodeButton
  Bridge.setStrProp nodeId Bridge.PropText (bcLabel config)
  callbackId <- registerCallback rs (bcAction config)
  Bridge.setHandler nodeId Bridge.EventClick callbackId
  applyFontConfig nodeId (bcFontConfig config)
  pure (RenderedLeaf (toUnit (Button config)) nodeId (Just callbackId))
createRenderedNode rs (TextInput config) = do
  nodeId <- Bridge.createNode Bridge.NodeTextInput
  Bridge.setStrProp nodeId Bridge.PropText (tiValue config)
  Bridge.setStrProp nodeId Bridge.PropHint (tiHint config)
  Bridge.setNumProp nodeId Bridge.PropInputType (fromIntegral (inputTypeToInt (tiInputType config)))
  callbackId <- registerTextCallback rs (tiOnChange config)
  Bridge.setHandler nodeId Bridge.EventTextChange callbackId
  applyFontConfig nodeId (tiFontConfig config)
  pure (RenderedLeaf (toUnit (TextInput config)) nodeId (Just callbackId))
createRenderedNode rs (Column children) = do
  nodeId <- Bridge.createNode Bridge.NodeColumn
  childNodes <- mapM (\child -> do
    childNode <- createRenderedNode rs child
    Bridge.addChild nodeId (renderedNodeId childNode)
    pure childNode
    ) children
  pure (RenderedContainer (Column (map toUnit children)) nodeId childNodes)
createRenderedNode rs (Row children) = do
  nodeId <- Bridge.createNode Bridge.NodeRow
  childNodes <- mapM (\child -> do
    childNode <- createRenderedNode rs child
    Bridge.addChild nodeId (renderedNodeId childNode)
    pure childNode
    ) children
  pure (RenderedContainer (Row (map toUnit children)) nodeId childNodes)
createRenderedNode rs (ScrollView children) = do
  nodeId <- Bridge.createNode Bridge.NodeScrollView
  childNodes <- mapM (\child -> do
    childNode <- createRenderedNode rs child
    Bridge.addChild nodeId (renderedNodeId childNode)
    pure childNode
    ) children
  pure (RenderedContainer (ScrollView (map toUnit children)) nodeId childNodes)
createRenderedNode _rs (Image config) = do
  nodeId <- Bridge.createNode Bridge.NodeImage
  case icSource config of
    ImageResource (ResourceName name) -> Bridge.setStrProp nodeId Bridge.PropImageResource name
    ImageData bytes                   -> Bridge.setImageData nodeId bytes
    ImageFile path                    -> Bridge.setStrProp nodeId Bridge.PropImageFile (pack path)
  Bridge.setNumProp nodeId Bridge.PropScaleType (scaleTypeToDouble (icScaleType config))
  pure (RenderedLeaf (toUnit (Image config)) nodeId Nothing)
createRenderedNode rs (WebView config) = do
  nodeId <- Bridge.createNode Bridge.NodeWebView
  Bridge.setStrProp nodeId Bridge.PropWebViewUrl (wvUrl config)
  maybeCallbackId <- case wvOnPageLoad config of
    Just action -> do
      callbackId <- registerCallback rs action
      Bridge.setHandler nodeId Bridge.EventClick callbackId
      pure (Just callbackId)
    Nothing -> pure Nothing
  pure (RenderedLeaf (toUnit (WebView config)) nodeId maybeCallbackId)
createRenderedNode rs (Styled style child) = do
  childNode <- createRenderedNode rs child
  applyStyle (renderedNodeId childNode) style
  pure (RenderedStyled (Styled style (toUnit child)) style childNode)

-- ---------------------------------------------------------------------------
-- Destroying rendered subtrees
-- ---------------------------------------------------------------------------

-- | Recursively destroy all native nodes in a rendered subtree.
destroyRenderedSubtree :: RenderedNode -> IO ()
destroyRenderedSubtree (RenderedLeaf _ nodeId _) =
  Bridge.destroyNode nodeId
destroyRenderedSubtree (RenderedContainer _ nodeId children) = do
  mapM_ destroyRenderedSubtree children
  Bridge.destroyNode nodeId
destroyRenderedSubtree (RenderedStyled _ _ child) =
  destroyRenderedSubtree child

-- ---------------------------------------------------------------------------
-- Incremental diff algorithm
-- ---------------------------------------------------------------------------

-- | Check whether two widgets use the same constructor (node type).
-- Does not compare contents — just the outermost constructor tag.
sameNodeType :: Widget () -> Widget () -> Bool
sameNodeType (Text _)        (Text _)        = True
sameNodeType (Button _)      (Button _)      = True
sameNodeType (TextInput _)   (TextInput _)   = True
sameNodeType (Column _)      (Column _)      = True
sameNodeType (Row _)         (Row _)         = True
sameNodeType (ScrollView _)  (ScrollView _)  = True
sameNodeType (Image _)       (Image _)       = True
sameNodeType (WebView _)     (WebView _)     = True
sameNodeType (Styled _ _)    (Styled _ _)    = True
sameNodeType _               _               = False

-- | Diff the old rendered tree against a new 'Widget User' and produce
-- an updated 'RenderedNode', emitting only the necessary bridge calls.
--
-- Cases:
-- 1. No old node → create from scratch.
-- 2. @toUnit new == rnUnitWidget old@ → reuse native node, re-register callbacks.
-- 3. Same container type, children differ → keep container, diff children.
-- 4. Same Styled, diff child recursively, re-apply style if changed.
-- 5. Same leaf type but properties differ → destroy old, create new.
-- 6. Different node type → destroy old subtree, create new.
diffRenderNode :: RenderState -> Maybe RenderedNode -> Widget User -> IO RenderedNode
-- Case 1: No previous node — create from scratch.
diffRenderNode rs Nothing newWidget =
  createRenderedNode rs newWidget

-- Case 2: Exact match — reuse native node, just re-register callbacks.
diffRenderNode rs (Just oldNode) newWidget
  | toUnit newWidget == renderedUnitWidget oldNode =
    reRegisterCallbacks rs oldNode newWidget

-- Case 4: Both are Styled — diff child recursively.
diffRenderNode rs (Just (RenderedStyled _ oldStyle oldChild)) (Styled newStyle newChild) = do
  diffedChild <- diffRenderNode rs (Just oldChild) newChild
  -- Re-apply style if it changed.
  if newStyle /= oldStyle
    then applyStyle (renderedNodeId diffedChild) newStyle
    else pure ()
  pure (RenderedStyled (Styled newStyle (toUnit newChild)) newStyle diffedChild)

-- Case 3: Same container type, children may differ — keep container, diff children.
diffRenderNode rs (Just oldNode@(RenderedContainer _ containerNodeId oldChildren)) newWidget
  | sameNodeType (renderedUnitWidget oldNode) (toUnit newWidget) =
    case newWidget of
      Column newChildren     -> diffContainer rs containerNodeId oldChildren newChildren (Column . map toUnit)
      Row newChildren        -> diffContainer rs containerNodeId oldChildren newChildren (Row . map toUnit)
      ScrollView newChildren -> diffContainer rs containerNodeId oldChildren newChildren (ScrollView . map toUnit)
      -- Non-container but same type at container level shouldn't happen,
      -- but fall through to destroy+create for safety.
      _ -> replaceNode rs oldNode newWidget

-- Case 5/6: Same leaf type with different properties, or completely different
-- node types — destroy old and create new.
diffRenderNode rs (Just oldNode) newWidget =
  replaceNode rs oldNode newWidget

-- | Diff container children: remove all children from parent, diff each
-- individually, then re-add all in correct order.
diffContainer :: RenderState -> Int32 -> [RenderedNode] -> [Widget User]
              -> ([Widget ()] -> Widget ()) -> IO RenderedNode
diffContainer rs containerNodeId oldChildren newChildren mkUnitWidget = do
  -- Remove all children from the container (order may change).
  mapM_ (\oldChild -> Bridge.removeChild containerNodeId (renderedNodeId oldChild)) oldChildren
  -- Diff each child position, pairing old children with new where available.
  let paired = zipPadded oldChildren newChildren
  diffedChildren <- mapM (\(maybeOld, newChild) ->
    diffRenderNode rs maybeOld newChild
    ) paired
  -- Destroy any excess old children that weren't paired.
  let excessOld = drop (length newChildren) oldChildren
  mapM_ destroyRenderedSubtree excessOld
  -- Re-add all children in the correct order.
  mapM_ (\child -> Bridge.addChild containerNodeId (renderedNodeId child)) diffedChildren
  pure (RenderedContainer (mkUnitWidget (map toUnit newChildren)) containerNodeId diffedChildren)

-- | Zip two lists, padding the shorter one with 'Nothing'.
-- Returns @(Maybe old, new)@ pairs covering all new elements.
zipPadded :: [a] -> [b] -> [(Maybe a, b)]
zipPadded [] newItems         = map (\new -> (Nothing, new)) newItems
zipPadded _ []                = []
zipPadded (old:olds) (new:news) = (Just old, new) : zipPadded olds news

-- | Destroy an old node and create a fresh replacement.
replaceNode :: RenderState -> RenderedNode -> Widget User -> IO RenderedNode
replaceNode rs oldNode newWidget = do
  destroyRenderedSubtree oldNode
  createRenderedNode rs newWidget

-- | Re-register callbacks for a node that is being reused (exact match).
-- The native view keeps its node ID; only the Haskell-side closures
-- are updated in the callback maps.
reRegisterCallbacks :: RenderState -> RenderedNode -> Widget User -> IO RenderedNode
reRegisterCallbacks rs (RenderedLeaf unitW nodeId maybeCbId) newWidget =
  case (newWidget, maybeCbId) of
    (Button config, Just cbId) -> do
      registerCallbackAt rs cbId (bcAction config)
      pure (RenderedLeaf unitW nodeId maybeCbId)
    (TextInput config, Just cbId) -> do
      registerTextCallbackAt rs cbId (tiOnChange config)
      pure (RenderedLeaf unitW nodeId maybeCbId)
    (WebView config, Just cbId) ->
      case wvOnPageLoad config of
        Just action -> do
          registerCallbackAt rs cbId action
          pure (RenderedLeaf unitW nodeId maybeCbId)
        Nothing ->
          pure (RenderedLeaf unitW nodeId maybeCbId)
    _ ->
      -- Text, Image, or leaf without callback — nothing to re-register.
      pure (RenderedLeaf unitW nodeId maybeCbId)

reRegisterCallbacks rs (RenderedContainer unitW nodeId oldChildren) newWidget =
  case newWidget of
    Column newChildren -> do
      reregisteredChildren <- reRegisterChildCallbacks (reRegisterCallbacks rs) oldChildren newChildren
      pure (RenderedContainer unitW nodeId reregisteredChildren)
    Row newChildren -> do
      reregisteredChildren <- reRegisterChildCallbacks (reRegisterCallbacks rs) oldChildren newChildren
      pure (RenderedContainer unitW nodeId reregisteredChildren)
    ScrollView newChildren -> do
      reregisteredChildren <- reRegisterChildCallbacks (reRegisterCallbacks rs) oldChildren newChildren
      pure (RenderedContainer unitW nodeId reregisteredChildren)
    _ ->
      -- Shouldn't happen (same unit widget implies same constructor),
      -- but return unchanged for safety.
      pure (RenderedContainer unitW nodeId oldChildren)

reRegisterCallbacks rs (RenderedStyled unitW style oldChild) (Styled _style newChild) = do
  reregisteredChild <- reRegisterCallbacks rs oldChild newChild
  pure (RenderedStyled unitW style reregisteredChild)
reRegisterCallbacks _rs styled@(RenderedStyled {}) _newWidget =
  -- Shouldn't happen (same unit widget implies Styled), but return unchanged.
  pure styled

-- | Re-register callbacks for paired old/new children.
-- Assumes the lists have the same length (caller guarantees via toUnit equality).
reRegisterChildCallbacks :: (RenderedNode -> Widget User -> IO RenderedNode)
                         -> [RenderedNode] -> [Widget User] -> IO [RenderedNode]
reRegisterChildCallbacks _reReg [] [] = pure []
reRegisterChildCallbacks reReg (old:olds) (new:news) = do
  result <- reReg old new
  rest <- reRegisterChildCallbacks reReg olds news
  pure (result : rest)
reRegisterChildCallbacks _reReg _ _ = pure []  -- mismatched lengths — shouldn't happen

-- ---------------------------------------------------------------------------
-- Top-level render entry point
-- ---------------------------------------------------------------------------

-- | Incremental render: diffs the new widget tree against the previously
-- rendered tree and emits only the necessary bridge operations.
--
-- On the first call (no previous tree), performs a full creation.
-- On subsequent calls, reuses unchanged native nodes.
renderWidget :: RenderState -> Widget User -> IO ()
renderWidget rs widget = do
  -- Clear callback maps for this render pass. rsNextId is NOT reset
  -- so reused nodes keep valid callback IDs and new nodes get fresh ones.
  clearCallbackMaps rs
  oldTree <- readIORef (rsRenderedTree rs)
  newTree <- diffRenderNode rs oldTree widget
  -- Set root if this is the first render or the root node changed.
  case oldTree of
    Nothing -> Bridge.setRoot (renderedNodeId newTree)
    Just old
      | renderedNodeId old /= renderedNodeId newTree ->
          Bridge.setRoot (renderedNodeId newTree)
      | otherwise -> pure ()
  writeIORef (rsRenderedTree rs) (Just newTree)

-- ---------------------------------------------------------------------------
-- Event dispatch
-- ---------------------------------------------------------------------------

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
