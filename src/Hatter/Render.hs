{-# LANGUAGE ImportQualifiedPost #-}
-- | Rendering engine that converts a 'Widget' tree into native UI
-- via the C bridge.
--
-- Uses an incremental diff strategy: on each render, the new widget
-- tree is compared (via derived 'Eq') against the previously rendered
-- tree.  Only changed subtrees are destroyed and recreated; unchanged
-- nodes keep their native views.
--
-- Callbacks are stored in a shared 'ActionState' registry that is
-- never cleared during rendering — handles inside widget configs
-- reference stable entries in the registry.
module Hatter.Render
  ( RenderState(..)
  , RenderedNode(..)
  , newRenderState
  , renderWidget
  , dispatchEvent
  , dispatchTextEvent
  )
where

import Control.Monad (when)
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.Int (Int32)
import Data.Text (Text, pack)
import Hatter.Action (Action(..), ActionState, OnChange(..), lookupAction, lookupTextAction)
import Hatter.Animation (AnimationState, registerTween)
import Hatter.Widget (AnimatedConfig(..), ButtonConfig(..), FontConfig(..), ImageConfig(..), ImageSource(..), InputType(..), MapViewConfig(..), ResourceName(..), ScaleType(..), TextAlignment(..), TextConfig(..), TextInputConfig(..), WebViewConfig(..), Widget(..), WidgetStyle(..), colorToHex, normalizeAnimated)
import Hatter.UIBridge qualified as Bridge
import System.IO (hPutStrLn, stderr)

-- ---------------------------------------------------------------------------
-- Rendered tree: retained structure for incremental diffing
-- ---------------------------------------------------------------------------

-- | A snapshot of a rendered widget, retaining the widget value
-- (for equality comparison) and native node IDs.
data RenderedNode
  = RenderedLeaf
      Widget         -- ^ Widget value for equality comparison.
      Int32          -- ^ Native node ID from the platform bridge.
  | RenderedContainer
      Widget         -- ^ Widget value (Column/Row/ScrollView with children).
      Int32          -- ^ Native node ID.
      [RenderedNode] -- ^ Rendered children.
  | RenderedStyled
      Widget         -- ^ Widget value (Styled wrapper).
      WidgetStyle    -- ^ Applied style (for change detection).
      RenderedNode   -- ^ Child (Styled doesn't own a native node).
  | RenderedAnimated
      Widget         -- ^ Full Animated widget (Animated config child) for Eq comparison.
      RenderedNode   -- ^ Child's rendered node (owns native node IDs).

-- | Get the native node ID for a rendered node.
-- 'RenderedStyled' follows through to its child's node ID.
renderedNodeId :: RenderedNode -> Int32
renderedNodeId (RenderedLeaf _ nodeId)         = nodeId
renderedNodeId (RenderedContainer _ nodeId _)  = nodeId
renderedNodeId (RenderedStyled _ _ child)      = renderedNodeId child
renderedNodeId (RenderedAnimated _ child)      = renderedNodeId child

-- | Get the widget value for a rendered node.
renderedWidget :: RenderedNode -> Widget
renderedWidget (RenderedLeaf widget _)        = widget
renderedWidget (RenderedContainer widget _ _) = widget
renderedWidget (RenderedStyled widget _ _)    = widget
renderedWidget (RenderedAnimated widget _)    = widget

-- ---------------------------------------------------------------------------
-- Render state
-- ---------------------------------------------------------------------------

-- | Mutable state for the rendering engine.
-- Holds a reference to the shared 'ActionState' callback registry
-- and the previously rendered tree for incremental diffing.
data RenderState = RenderState
  { rsActionState    :: ActionState
    -- ^ Shared callback registry (never cleared during rendering).
  , rsRenderedTree   :: IORef (Maybe RenderedNode)
    -- ^ The previously rendered tree, or 'Nothing' for the first render.
  , rsAnimationState :: AnimationState
    -- ^ Mutable animation tween registry.
  }

-- | Create a fresh 'RenderState' wrapping the given 'ActionState'
-- and 'AnimationState'.
newRenderState :: ActionState -> AnimationState -> IO RenderState
newRenderState actionState animState = do
  renderedTree <- newIORef Nothing
  pure RenderState
    { rsActionState    = actionState
    , rsRenderedTree   = renderedTree
    , rsAnimationState = animState
    }

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
  case wsTranslateX style of
    Just tx -> Bridge.setNumProp nodeId Bridge.PropTranslateX tx
    Nothing -> pure ()
  case wsTranslateY style of
    Just ty -> Bridge.setNumProp nodeId Bridge.PropTranslateY ty
    Nothing -> pure ()

-- ---------------------------------------------------------------------------
-- Creating rendered nodes from scratch
-- ---------------------------------------------------------------------------

-- | Create a native node from a 'Widget', returning a 'RenderedNode'
-- snapshot. Used for fresh creation (no old node to diff against).
createRenderedNode :: AnimationState -> Widget -> IO RenderedNode
createRenderedNode _animState widget@(Text config) = do
  nodeId <- Bridge.createNode Bridge.NodeText
  Bridge.setStrProp nodeId Bridge.PropText (tcLabel config)
  applyFontConfig nodeId (tcFontConfig config)
  pure (RenderedLeaf widget nodeId)
createRenderedNode _animState widget@(Button config) = do
  nodeId <- Bridge.createNode Bridge.NodeButton
  Bridge.setStrProp nodeId Bridge.PropText (bcLabel config)
  Bridge.setHandler nodeId Bridge.EventClick (actionId (bcAction config))
  applyFontConfig nodeId (bcFontConfig config)
  pure (RenderedLeaf widget nodeId)
createRenderedNode _animState widget@(TextInput config) = do
  nodeId <- Bridge.createNode Bridge.NodeTextInput
  Bridge.setStrProp nodeId Bridge.PropText (tiValue config)
  Bridge.setStrProp nodeId Bridge.PropHint (tiHint config)
  Bridge.setNumProp nodeId Bridge.PropInputType (fromIntegral (inputTypeToInt (tiInputType config)))
  Bridge.setHandler nodeId Bridge.EventTextChange (onChangeId (tiOnChange config))
  applyFontConfig nodeId (tiFontConfig config)
  when (tiAutoFocus config) $
    Bridge.setNumProp nodeId Bridge.PropAutoFocus 1.0
  pure (RenderedLeaf widget nodeId)
createRenderedNode animState widget@(Column children) = do
  nodeId <- Bridge.createNode Bridge.NodeColumn
  childNodes <- mapM (\child -> do
    childNode <- createRenderedNode animState child
    Bridge.addChild nodeId (renderedNodeId childNode)
    pure childNode
    ) children
  pure (RenderedContainer widget nodeId childNodes)
createRenderedNode animState widget@(Row children) = do
  nodeId <- Bridge.createNode Bridge.NodeRow
  childNodes <- mapM (\child -> do
    childNode <- createRenderedNode animState child
    Bridge.addChild nodeId (renderedNodeId childNode)
    pure childNode
    ) children
  pure (RenderedContainer widget nodeId childNodes)
createRenderedNode animState widget@(ScrollView children) = do
  nodeId <- Bridge.createNode Bridge.NodeScrollView
  childNodes <- mapM (\child -> do
    childNode <- createRenderedNode animState child
    Bridge.addChild nodeId (renderedNodeId childNode)
    pure childNode
    ) children
  pure (RenderedContainer widget nodeId childNodes)
createRenderedNode _animState widget@(Image config) = do
  nodeId <- Bridge.createNode Bridge.NodeImage
  case icSource config of
    ImageResource (ResourceName name) -> Bridge.setStrProp nodeId Bridge.PropImageResource name
    ImageData bytes                   -> Bridge.setImageData nodeId bytes
    ImageFile path                    -> Bridge.setStrProp nodeId Bridge.PropImageFile (pack path)
  Bridge.setNumProp nodeId Bridge.PropScaleType (scaleTypeToDouble (icScaleType config))
  pure (RenderedLeaf widget nodeId)
createRenderedNode _animState widget@(WebView config) = do
  nodeId <- Bridge.createNode Bridge.NodeWebView
  Bridge.setStrProp nodeId Bridge.PropWebViewUrl (wvUrl config)
  case wvOnPageLoad config of
    Just action -> Bridge.setHandler nodeId Bridge.EventClick (actionId action)
    Nothing     -> pure ()
  pure (RenderedLeaf widget nodeId)
createRenderedNode _animState widget@(MapView config) = do
  nodeId <- Bridge.createNode Bridge.NodeMapView
  Bridge.setNumProp nodeId Bridge.PropMapLat (mvLatitude config)
  Bridge.setNumProp nodeId Bridge.PropMapLon (mvLongitude config)
  Bridge.setNumProp nodeId Bridge.PropMapZoom (mvZoom config)
  Bridge.setNumProp nodeId Bridge.PropMapShowUserLoc
    (if mvShowUserLocation config then 1.0 else 0.0)
  case mvOnRegionChange config of
    Just onChange -> Bridge.setHandler nodeId Bridge.EventTextChange
                      (onChangeId onChange)
    Nothing      -> pure ()
  pure (RenderedLeaf widget nodeId)
createRenderedNode animState widget@(Styled style child) = do
  childNode <- createRenderedNode animState child
  applyStyle (renderedNodeId childNode) style
  pure (RenderedStyled widget style childNode)
createRenderedNode animState (Animated config child) = do
  let normalized = normalizeAnimated config child
  case normalized of
    -- normalizeAnimated distributed into a container — render the container directly
    -- (each child is now individually wrapped in Animated).
    Column _     -> createRenderedNode animState normalized
    Row _        -> createRenderedNode animState normalized
    ScrollView _ -> createRenderedNode animState normalized
    -- Everything else (Styled, leaves): wrap in RenderedAnimated for tween interpolation.
    _            -> do
      let finalWidget = Animated config normalized
      childNode <- createRenderedNode animState normalized
      pure (RenderedAnimated finalWidget childNode)

-- ---------------------------------------------------------------------------
-- Destroying rendered subtrees
-- ---------------------------------------------------------------------------

-- | Recursively destroy all native nodes in a rendered subtree.
destroyRenderedSubtree :: RenderedNode -> IO ()
destroyRenderedSubtree (RenderedLeaf _ nodeId) =
  Bridge.destroyNode nodeId
destroyRenderedSubtree (RenderedContainer _ nodeId children) = do
  mapM_ destroyRenderedSubtree children
  Bridge.destroyNode nodeId
destroyRenderedSubtree (RenderedStyled _ _ child) =
  destroyRenderedSubtree child
destroyRenderedSubtree (RenderedAnimated _ child) =
  destroyRenderedSubtree child

-- ---------------------------------------------------------------------------
-- Incremental diff algorithm
-- ---------------------------------------------------------------------------

-- | Check whether two widgets use the same constructor (node type).
-- Does not compare contents — just the outermost constructor tag.
sameNodeType :: Widget -> Widget -> Bool
sameNodeType (Text _)        (Text _)        = True
sameNodeType (Button _)      (Button _)      = True
sameNodeType (TextInput _)   (TextInput _)   = True
sameNodeType (Column _)      (Column _)      = True
sameNodeType (Row _)         (Row _)         = True
sameNodeType (ScrollView _)  (ScrollView _)  = True
sameNodeType (Image _)       (Image _)       = True
sameNodeType (WebView _)     (WebView _)     = True
sameNodeType (MapView _)     (MapView _)     = True
sameNodeType (Styled _ _)    (Styled _ _)    = True
sameNodeType (Animated _ _)  (Animated _ _)  = True
sameNodeType _               _               = False

-- | Diff the old rendered tree against a new 'Widget' and produce
-- an updated 'RenderedNode', emitting only the necessary bridge calls.
--
-- Cases:
-- 1. No old node -> create from scratch.
-- 2. @newWidget == renderedWidget oldNode@ -> reuse native node entirely (zero work).
-- 3. Same container type, children differ -> keep container, diff children.
-- 4. Same Styled, diff child recursively, re-apply style if changed.
-- 5. Same leaf type but properties differ -> destroy old, create new.
-- 6. Different node type -> destroy old subtree, create new.
diffRenderNode :: AnimationState -> Maybe RenderedNode -> Widget -> IO RenderedNode
-- Case 1: No previous node — create from scratch.
diffRenderNode animState Nothing newWidget =
  createRenderedNode animState newWidget

-- Case 2: Exact match — reuse native node entirely.
diffRenderNode _animState (Just oldNode) newWidget
  | newWidget == renderedWidget oldNode =
    pure oldNode

-- Case: Animated wrapping a container — normalize (distribute to children) and recurse.
diffRenderNode animState maybeOld (Animated config child@(Column _)) =
  diffRenderNode animState maybeOld (normalizeAnimated config child)
diffRenderNode animState maybeOld (Animated config child@(Row _)) =
  diffRenderNode animState maybeOld (normalizeAnimated config child)
diffRenderNode animState maybeOld (Animated config child@(ScrollView _)) =
  diffRenderNode animState maybeOld (normalizeAnimated config child)
-- Case: Nested Animated — inner config wins.
diffRenderNode animState maybeOld (Animated _outerConfig child@(Animated _ _)) =
  diffRenderNode animState maybeOld child

-- Case: Both are Animated (leaf) — diff the child, possibly registering a tween.
diffRenderNode animState (Just (RenderedAnimated _ oldChildNode)) (Animated newConfig newChild) = do
  let oldChildWidget = renderedWidget oldChildNode
  if sameNodeType oldChildWidget newChild
    then do
      -- Same child node type: keep native node, register tween if properties differ
      if oldChildWidget /= newChild
        then registerTween animState (renderedNodeId oldChildNode)
               oldChildWidget newChild (anDuration newConfig) (anEasing newConfig)
        else pure ()
      -- Update the RenderedAnimated to reflect the new target
      pure (RenderedAnimated (Animated newConfig newChild) oldChildNode)
    else do
      -- Different child type: can't animate, destroy+create
      destroyRenderedSubtree oldChildNode
      newChildNode <- createRenderedNode animState newChild
      pure (RenderedAnimated (Animated newConfig newChild) newChildNode)

-- Case 4: Both are Styled — diff child recursively.
diffRenderNode animState (Just (RenderedStyled _ oldStyle oldChild)) (Styled newStyle newChild) = do
  diffedChild <- diffRenderNode animState (Just oldChild) newChild
  if newStyle /= oldStyle
    then applyStyle (renderedNodeId diffedChild) newStyle
    else pure ()
  pure (RenderedStyled (Styled newStyle newChild) newStyle diffedChild)

-- Case 3: Same container type, children may differ — keep container, diff children.
diffRenderNode animState (Just oldNode@(RenderedContainer _ containerNodeId oldChildren)) newWidget
  | sameNodeType (renderedWidget oldNode) newWidget =
    case newWidget of
      Column newChildren     -> diffContainer animState containerNodeId oldChildren newChildren newWidget
      Row newChildren        -> diffContainer animState containerNodeId oldChildren newChildren newWidget
      ScrollView newChildren -> diffContainer animState containerNodeId oldChildren newChildren newWidget
      -- Non-container but same type at container level shouldn't happen,
      -- but fall through to destroy+create for safety.
      _ -> replaceNode animState oldNode newWidget

-- Case 5/6: Same leaf type with different properties, or completely different
-- node types — destroy old and create new.
diffRenderNode animState (Just oldNode) newWidget =
  replaceNode animState oldNode newWidget

-- | Diff container children: remove all children from parent, diff each
-- individually, then re-add all in correct order.
diffContainer :: AnimationState -> Int32 -> [RenderedNode] -> [Widget]
              -> Widget -> IO RenderedNode
diffContainer animState containerNodeId oldChildren newChildren newWidget = do
  -- Remove all children from the container (order may change).
  mapM_ (\oldChild -> Bridge.removeChild containerNodeId (renderedNodeId oldChild)) oldChildren
  -- Diff each child position, pairing old children with new where available.
  let paired = zipPadded oldChildren newChildren
  diffedChildren <- mapM (\(maybeOld, newChild) ->
    diffRenderNode animState maybeOld newChild
    ) paired
  -- Destroy any excess old children that weren't paired.
  let excessOld = drop (length newChildren) oldChildren
  mapM_ destroyRenderedSubtree excessOld
  -- Re-add all children in the correct order.
  mapM_ (\child -> Bridge.addChild containerNodeId (renderedNodeId child)) diffedChildren
  pure (RenderedContainer newWidget containerNodeId diffedChildren)

-- | Zip two lists, padding the shorter one with 'Nothing'.
-- Returns @(Maybe old, new)@ pairs covering all new elements.
zipPadded :: [a] -> [b] -> [(Maybe a, b)]
zipPadded [] newItems           = map (\new -> (Nothing, new)) newItems
zipPadded _ []                  = []
zipPadded (old:olds) (new:news) = (Just old, new) : zipPadded olds news

-- | Destroy an old node and create a fresh replacement.
replaceNode :: AnimationState -> RenderedNode -> Widget -> IO RenderedNode
replaceNode animState oldNode newWidget = do
  destroyRenderedSubtree oldNode
  createRenderedNode animState newWidget

-- ---------------------------------------------------------------------------
-- Top-level render entry point
-- ---------------------------------------------------------------------------

-- | Incremental render: diffs the new widget tree against the previously
-- rendered tree and emits only the necessary bridge operations.
--
-- On the first call (no previous tree), performs a full creation.
-- On subsequent calls, reuses unchanged native nodes.
renderWidget :: RenderState -> Widget -> IO ()
renderWidget rs widget = do
  oldTree <- readIORef (rsRenderedTree rs)
  newTree <- diffRenderNode (rsAnimationState rs) oldTree widget
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
