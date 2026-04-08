{-# LANGUAGE ForeignFunctionInterface #-}
-- | Low-level FFI bindings to the C UI bridge (@cbits/ui_bridge.c@).
--
-- These functions delegate to platform-native implementations on
-- Android/iOS and fall back to stderr stubs on desktop.
module HaskellMobile.UIBridge
  ( NodeType(..)
  , nodeTypeToInt
  , PropId(..)
  , propIdToInt
  , EventType(..)
  , eventTypeToInt
  , createNode
  , setStrProp
  , setNumProp
  , setImageData
  , setHandler
  , addChild
  , removeChild
  , destroyNode
  , setRoot
  , clear
  )
where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Int (Int32)
import Data.Text (Text, unpack)
import Data.Word (Word8)
import Foreign.C.String (CString, withCString)
import Foreign.C.Types (CInt(..), CDouble(..))
import Foreign.Ptr (Ptr, castPtr)

-- | Widget node types corresponding to @UI_NODE_*@ in @UIBridge.h@.
data NodeType
  = NodeText
  | NodeButton
  | NodeColumn
  | NodeRow
  | NodeTextInput
  | NodeScrollView
  | NodeImage
  deriving (Show, Eq, Enum, Bounded)

-- | Map a 'NodeType' to its C integer code.
nodeTypeToInt :: NodeType -> Int32
nodeTypeToInt NodeText       = 0
nodeTypeToInt NodeButton     = 1
nodeTypeToInt NodeColumn     = 2
nodeTypeToInt NodeRow        = 3
nodeTypeToInt NodeTextInput  = 4
nodeTypeToInt NodeScrollView = 5
nodeTypeToInt NodeImage      = 6

-- | Property identifiers for 'setStrProp' and 'setNumProp'.
data PropId
  = PropText
  | PropColor
  | PropHint
  | PropBgColor
  | PropFontSize
  | PropPadding
  | PropInputType
  | PropGravity
  | PropImageResource
  | PropImageFile
  | PropScaleType
  deriving (Show, Eq, Enum, Bounded)

-- | Map a 'PropId' to its C integer code.
propIdToInt :: PropId -> Int32
propIdToInt PropText          = 0
propIdToInt PropColor         = 1
propIdToInt PropHint          = 2
propIdToInt PropBgColor       = 3
propIdToInt PropImageResource = 4
propIdToInt PropImageFile     = 5
propIdToInt PropFontSize      = 0
propIdToInt PropPadding       = 1
propIdToInt PropInputType     = 2
propIdToInt PropGravity       = 3
propIdToInt PropScaleType     = 4

-- | Event types corresponding to @UI_EVENT_*@ in @UIBridge.h@.
data EventType
  = EventClick
  | EventTextChange
  deriving (Show, Eq, Enum, Bounded)

-- | Map an 'EventType' to its C integer code.
eventTypeToInt :: EventType -> Int32
eventTypeToInt EventClick      = 0
eventTypeToInt EventTextChange = 1

-- Raw FFI imports
foreign import ccall "ui_create_node"    c_createNode   :: CInt -> IO CInt
foreign import ccall "ui_set_str_prop"   c_setStrProp   :: CInt -> CInt -> CString -> IO ()
foreign import ccall "ui_set_num_prop"   c_setNumProp   :: CInt -> CInt -> CDouble -> IO ()
foreign import ccall "ui_set_image_data" c_setImageData :: CInt -> Ptr Word8 -> CInt -> IO ()
foreign import ccall "ui_set_handler"    c_setHandler   :: CInt -> CInt -> CInt -> IO ()
foreign import ccall "ui_add_child"      c_addChild     :: CInt -> CInt -> IO ()
foreign import ccall "ui_remove_child"   c_removeChild  :: CInt -> CInt -> IO ()
foreign import ccall "ui_destroy_node"   c_destroyNode  :: CInt -> IO ()
foreign import ccall "ui_set_root"       c_setRoot      :: CInt -> IO ()
foreign import ccall "ui_clear"          c_clear        :: IO ()

-- | Create a native node of the given type. Returns an opaque node ID.
createNode :: NodeType -> IO Int32
createNode nt = fromIntegral <$> c_createNode (fromIntegral (nodeTypeToInt nt))

-- | Set a string property on a node.
setStrProp :: Int32 -> PropId -> Text -> IO ()
setStrProp nodeId propId value =
  withCString (unpack value) $ \cstr ->
    c_setStrProp (fromIntegral nodeId) (fromIntegral (propIdToInt propId)) cstr

-- | Set a numeric property on a node.
setNumProp :: Int32 -> PropId -> Double -> IO ()
setNumProp nodeId propId value =
  c_setNumProp (fromIntegral nodeId) (fromIntegral (propIdToInt propId)) (realToFrac value)

-- | Set raw image data (PNG/JPEG bytes) on a node.
setImageData :: Int32 -> ByteString -> IO ()
setImageData nodeId imageBytes =
  BS.useAsCStringLen imageBytes $ \(ptr, len) ->
    c_setImageData (fromIntegral nodeId) (castPtr ptr) (fromIntegral len)

-- | Register an event handler on a node. The @callbackId@ is looked up
-- in the 'RenderState' callback registry when the event fires.
setHandler :: Int32 -> EventType -> Int32 -> IO ()
setHandler nodeId eventType callbackId =
  c_setHandler (fromIntegral nodeId) (fromIntegral (eventTypeToInt eventType)) (fromIntegral callbackId)

-- | Add a child node to a parent container.
addChild :: Int32 -> Int32 -> IO ()
addChild parentId childId =
  c_addChild (fromIntegral parentId) (fromIntegral childId)

-- | Remove a child node from a parent container.
removeChild :: Int32 -> Int32 -> IO ()
removeChild parentId childId =
  c_removeChild (fromIntegral parentId) (fromIntegral childId)

-- | Destroy a node and free its native resources.
destroyNode :: Int32 -> IO ()
destroyNode nodeId =
  c_destroyNode (fromIntegral nodeId)

-- | Set a node as the root of the display.
setRoot :: Int32 -> IO ()
setRoot nodeId =
  c_setRoot (fromIntegral nodeId)

-- | Clear all nodes (called before re-render).
clear :: IO ()
clear = c_clear
