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
import Data.IntMap.Strict (IntMap)
import Data.IntMap.Strict qualified as IntMap
import Data.IntSet (IntSet)
import Data.IntSet qualified as IntSet
import Data.Text (Text, pack)
import Hatter.Action (Action(..), ActionState, OnChange(..), lookupAction, lookupTextAction)
import Hatter.Animation (AnimationState, registerTween)
import Hatter.Widget (AnimatedConfig(..), ButtonConfig(..), FontConfig(..), ImageConfig(..), ImageSource(..), InputType(..), LayoutItem(..), LayoutSettings(..), MapViewConfig(..), ResourceName(..), ScaleType(..), TextAlignment(..), TextConfig(..), TextInputConfig(..), WebViewConfig(..), Widget(..), WidgetStyle(..), colorToHex, normalizeAnimated, resolveKeyAtIndex, zeroAnimationOrigin)

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
      Widget              -- ^ Widget value (Column/Row/Stack with children).
      Int32               -- ^ Native node ID.
      [(Int, RenderedNode)] -- ^ Rendered children, keyed by resolved WidgetKey value.
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

-- | Update the widget stored in a RenderedNode to reflect an animation target.
-- The native node ID and children are preserved; only the bookkeeping fields
-- (widget, style) change so the next diff sees the post-animation state.
updateRenderedTarget :: Widget -> RenderedNode -> RenderedNode
updateRenderedTarget target (RenderedLeaf _ nodeId) =
  RenderedLeaf target nodeId
updateRenderedTarget target (RenderedContainer _ nodeId children) =
  RenderedContainer target nodeId children
updateRenderedTarget (Styled newStyle _) (RenderedStyled _ _ child) =
  RenderedStyled (Styled newStyle (renderedWidget child)) newStyle child
updateRenderedTarget target (RenderedStyled _ oldStyle child) =
  RenderedStyled target oldStyle child
updateRenderedTarget target (RenderedAnimated _ child) =
  RenderedAnimated target child

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
  case wsTouchPassthrough style of
    Just enabled -> Bridge.setNumProp nodeId Bridge.PropTouchPassthrough
                      (if enabled then 1.0 else 0.0)
    Nothing      -> pure ()

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
createRenderedNode animState widget@(Column settings) = do
  let nodeType = if lsScrollable settings
        then Bridge.NodeScrollView
        else Bridge.NodeColumn
  nodeId <- Bridge.createNode nodeType
  keyedChildren <- mapM (\(index, layoutItem) -> do
    let keyVal = resolveKeyAtIndex index layoutItem
    childNode <- createRenderedNode animState (liWidget layoutItem)
    Bridge.addChild nodeId (renderedNodeId childNode)
    pure (keyVal, childNode)
    ) (zip [0..] (lsWidgets settings))
  pure (RenderedContainer widget nodeId keyedChildren)
createRenderedNode animState widget@(Row settings) = do
  let nodeType = if lsScrollable settings
        then Bridge.NodeHorizontalScrollView
        else Bridge.NodeRow
  nodeId <- Bridge.createNode nodeType
  keyedChildren <- mapM (\(index, layoutItem) -> do
    let keyVal = resolveKeyAtIndex index layoutItem
    childNode <- createRenderedNode animState (liWidget layoutItem)
    Bridge.addChild nodeId (renderedNodeId childNode)
    pure (keyVal, childNode)
    ) (zip [0..] (lsWidgets settings))
  pure (RenderedContainer widget nodeId keyedChildren)
createRenderedNode animState widget@(Stack items) = do
  nodeId <- Bridge.createNode Bridge.NodeStack
  keyedChildren <- mapM (\(index, layoutItem) -> do
    let keyVal = resolveKeyAtIndex index layoutItem
    childNode <- createRenderedNode animState (liWidget layoutItem)
    Bridge.addChild nodeId (renderedNodeId childNode)
    pure (keyVal, childNode)
    ) (zip [0..] items)
  pure (RenderedContainer widget nodeId keyedChildren)
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
    Stack _      -> createRenderedNode animState normalized
    -- Everything else (Styled, leaves): wrap in RenderedAnimated for tween interpolation.
    -- Create the native node at the zero-origin position and register a tween
    -- from zero to the target, so the first render animates into place.
    _            -> do
      let finalWidget = Animated config normalized
          zeroOrigin = zeroAnimationOrigin normalized
      childNode <- createRenderedNode animState zeroOrigin
      if zeroOrigin /= normalized
        then do
          registerTween animState (renderedNodeId childNode)
            zeroOrigin normalized (anDuration config) (anEasing config)
          -- Store the target widget (not zero) so subsequent diffs see
          -- the correct post-animation state.
          let targetChildNode = updateRenderedTarget normalized childNode
          pure (RenderedAnimated finalWidget targetChildNode)
        else
          pure (RenderedAnimated finalWidget childNode)

-- ---------------------------------------------------------------------------
-- Destroying rendered subtrees
-- ---------------------------------------------------------------------------

-- | Recursively destroy all native nodes in a rendered subtree.
destroyRenderedSubtree :: RenderedNode -> IO ()
destroyRenderedSubtree (RenderedLeaf _ nodeId) =
  Bridge.destroyNode nodeId
destroyRenderedSubtree (RenderedContainer _ nodeId keyedChildren) = do
  mapM_ (destroyRenderedSubtree . snd) keyedChildren
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
sameNodeType (Column a)      (Column b)      = lsScrollable a == lsScrollable b
sameNodeType (Row a)         (Row b)         = lsScrollable a == lsScrollable b
sameNodeType (Stack _)       (Stack _)       = True
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
diffRenderNode animState maybeOld (Animated config child@(Stack _)) =
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
      let updatedChildNode = updateRenderedTarget newChild oldChildNode
      pure (RenderedAnimated (Animated newConfig newChild) updatedChildNode)
    else do
      -- Different child type: can't animate, destroy+create
      destroyRenderedSubtree oldChildNode
      newChildNode <- createRenderedNode animState newChild
      pure (RenderedAnimated (Animated newConfig newChild) newChildNode)

-- Case 4: Both are Styled — diff child recursively.
diffRenderNode animState (Just (RenderedStyled _ oldStyle oldChild)) (Styled newStyle newChild) = do
  diffedChild <- diffRenderNode animState (Just oldChild) newChild
  let nodeChanged = renderedNodeId diffedChild /= renderedNodeId oldChild
  if newStyle /= oldStyle || nodeChanged
    then applyStyle (renderedNodeId diffedChild) newStyle
    else pure ()
  pure (RenderedStyled (Styled newStyle newChild) newStyle diffedChild)

-- Case 3: Same container type, children may differ — keep container, diff children.
diffRenderNode animState (Just oldNode@(RenderedContainer _ containerNodeId oldKeyedChildren)) newWidget
  | sameNodeType (renderedWidget oldNode) newWidget =
    case newWidget of
      Column settings        -> diffContainer animState containerNodeId oldKeyedChildren (lsWidgets settings) newWidget
      Row settings           -> diffContainer animState containerNodeId oldKeyedChildren (lsWidgets settings) newWidget
      Stack newItems         -> diffContainer animState containerNodeId oldKeyedChildren newItems newWidget
      -- Non-container but same type at container level shouldn't happen,
      -- but fall through to destroy+create for safety.
      _ -> replaceNode animState oldNode newWidget

-- Case: Text in-place update — keep native node, only update changed
-- properties.  Avoids destroying and recreating sibling nodes in a
-- Column, which would detach EditText from the view hierarchy and
-- disconnect the IME (see TextInput case below).
diffRenderNode _animState (Just (RenderedLeaf (Text oldConfig) nodeId)) newWidget@(Text newConfig) = do
  if tcLabel oldConfig /= tcLabel newConfig
    then Bridge.setStrProp nodeId Bridge.PropText (tcLabel newConfig)
    else pure ()
  if tcFontConfig oldConfig /= tcFontConfig newConfig
    then applyFontConfig nodeId (tcFontConfig newConfig)
    else pure ()
  pure (RenderedLeaf newWidget nodeId)

-- Case: Button in-place update — keep native node, only update changed
-- properties.
diffRenderNode _animState (Just (RenderedLeaf (Button oldConfig) nodeId)) newWidget@(Button newConfig) = do
  if bcLabel oldConfig /= bcLabel newConfig
    then Bridge.setStrProp nodeId Bridge.PropText (bcLabel newConfig)
    else pure ()
  if actionId (bcAction oldConfig) /= actionId (bcAction newConfig)
    then Bridge.setHandler nodeId Bridge.EventClick (actionId (bcAction newConfig))
    else pure ()
  if bcFontConfig oldConfig /= bcFontConfig newConfig
    then applyFontConfig nodeId (bcFontConfig newConfig)
    else pure ()
  pure (RenderedLeaf newWidget nodeId)

-- Case: TextInput in-place update — keep native node to preserve
-- cursor position and focus. Only sends bridge calls for properties
-- that actually changed.
diffRenderNode _animState (Just (RenderedLeaf (TextInput oldConfig) nodeId)) newWidget@(TextInput newConfig) = do
  if tiValue oldConfig /= tiValue newConfig
    then Bridge.setStrProp nodeId Bridge.PropText (tiValue newConfig)
    else pure ()
  if tiHint oldConfig /= tiHint newConfig
    then Bridge.setStrProp nodeId Bridge.PropHint (tiHint newConfig)
    else pure ()
  if tiInputType oldConfig /= tiInputType newConfig
    then Bridge.setNumProp nodeId Bridge.PropInputType
           (fromIntegral (inputTypeToInt (tiInputType newConfig)))
    else pure ()
  if onChangeId (tiOnChange oldConfig) /= onChangeId (tiOnChange newConfig)
    then Bridge.setHandler nodeId Bridge.EventTextChange
           (onChangeId (tiOnChange newConfig))
    else pure ()
  if tiFontConfig oldConfig /= tiFontConfig newConfig
    then applyFontConfig nodeId (tiFontConfig newConfig)
    else pure ()
  pure (RenderedLeaf newWidget nodeId)

-- Case 5/6: Same leaf type with different properties, or completely different
-- node types — destroy old and create new.
diffRenderNode animState (Just oldNode) newWidget =
  replaceNode animState oldNode newWidget

-- | Diff container children by key.  Matches new children against old
-- by resolved 'WidgetKey', so inserting a child at position 0 no longer
-- causes all subsequent children to mismatch.  When all children maintain
-- their native node IDs and ordering, skip the remove/add cycle
-- entirely — this preserves IME state on EditText siblings.
diffContainer :: AnimationState -> Int32 -> [(Int, RenderedNode)] -> [LayoutItem]
              -> Widget -> IO RenderedNode
diffContainer animState containerNodeId oldKeyedChildren newLayoutItems newWidget = do
  -- Build IntMap from old children's stored keys (first occurrence wins on dup)
  let oldKeyMap = IntMap.fromList oldKeyedChildren
  -- Match new children against old by key (index-based for unkeyed items)
  (diffedKeyedChildren, usedKeySet) <- matchNewChildren animState oldKeyMap newLayoutItems
  -- Destroy unmatched old children
  let unusedOld = IntMap.withoutKeys oldKeyMap usedKeySet
  -- Check if native ordering is stable (same node IDs in same order)
  let oldIds = map (renderedNodeId . snd) oldKeyedChildren
  let newIds = map (renderedNodeId . snd) diffedKeyedChildren
  if oldIds == newIds
    then
      -- Stable: only remove+destroy unused old children
      mapM_ (\oldChild -> do
        Bridge.removeChild containerNodeId (renderedNodeId oldChild)
        destroyRenderedSubtree oldChild
        ) (IntMap.elems unusedOld)
    else do
      -- Ordering changed: full remove-all + re-add-all
      mapM_ (\oldChild -> Bridge.removeChild containerNodeId (renderedNodeId oldChild)) (map snd oldKeyedChildren)
      mapM_ destroyRenderedSubtree (IntMap.elems unusedOld)
      mapM_ (\child -> Bridge.addChild containerNodeId (renderedNodeId child)) (map snd diffedKeyedChildren)
  pure (RenderedContainer newWidget containerNodeId diffedKeyedChildren)

-- | Match new children against old children by resolved key.
-- Children without explicit keys use their list index as the key,
-- so they match by position.  Children with explicit keys match by key
-- regardless of position.
matchNewChildren :: AnimationState -> IntMap RenderedNode
                 -> [LayoutItem] -> IO ([(Int, RenderedNode)], IntSet)
matchNewChildren animState oldKeyMap newItems =
    go IntSet.empty (zip [0..] newItems)
  where
    go :: IntSet -> [(Int, LayoutItem)]
       -> IO ([(Int, RenderedNode)], IntSet)
    go usedKeys [] = pure ([], usedKeys)
    go usedKeys ((index, layoutItem) : rest) = do
      let keyVal = resolveKeyAtIndex index layoutItem
          newChild = liWidget layoutItem
          maybeOld = if IntSet.member keyVal usedKeys
                     then Nothing
                     else IntMap.lookup keyVal oldKeyMap
      diffedChild <- case maybeOld of
        Just oldChild ->
          if sameNodeType (renderedWidget oldChild) newChild
            then diffRenderNode animState (Just oldChild) newChild
            else do
              destroyRenderedSubtree oldChild
              createRenderedNode animState newChild
        Nothing ->
          createRenderedNode animState newChild
      let usedKeys' = case maybeOld of
            Just _  -> IntSet.insert keyVal usedKeys
            Nothing -> usedKeys
      (restNodes, finalUsed) <- go usedKeys' rest
      pure ((keyVal, diffedChild) : restNodes, finalUsed)

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
-- The caller ('Hatter.haskellOnUITextChange') triggers a re-render
-- after dispatch; the diff algorithm updates TextInput nodes in-place
-- so the native widget is preserved (no cursor reset or flicker).
-- Logs an error to stderr if the callbackId is not found.
dispatchTextEvent :: RenderState -> Int32 -> Text -> IO ()
dispatchTextEvent rs callbackId newText = do
  maybeAction <- lookupTextAction (rsActionState rs) callbackId
  case maybeAction of
    Just action -> action newText
    Nothing     -> hPutStrLn stderr $
      "dispatchTextEvent: unknown callback ID " ++ show callbackId
