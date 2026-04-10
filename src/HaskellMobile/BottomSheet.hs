{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE OverloadedStrings #-}
-- | Bottom sheet / action menu API for mobile platforms.
--
-- Provides an imperative API for showing platform-native bottom sheets
-- (Android BottomSheetDialog, iOS UISheetPresentationController,
-- watchOS .confirmationDialog).
-- Bottom sheets are fire-and-forget: the platform manages the sheet lifecycle
-- independently of the Haskell UI rendering loop.
--
-- The callback registry follows the same sequential 'IORef' 'Int32'
-- pattern used by "HaskellMobile.Dialog" and "HaskellMobile.Permission".
module HaskellMobile.BottomSheet
  ( BottomSheetAction(..)
  , BottomSheetConfig(..)
  , BottomSheetState(..)
  , newBottomSheetState
  , bottomSheetActionFromInt
  , showBottomSheet
  , dispatchBottomSheetResult
  )
where

import Data.IORef (IORef, newIORef, readIORef, writeIORef, modifyIORef')
import Data.Int (Int32)
import Data.IntMap.Strict (IntMap)
import Data.IntMap.Strict qualified as IntMap
import Data.Text (Text)
import Data.Text qualified as Text
import Foreign.C.String (CString, withCString)
import Foreign.C.Types (CInt(..))
import Foreign.Ptr (Ptr, nullPtr)
import System.IO (hPutStrLn, stderr)

-- | Result of a bottom sheet interaction.
data BottomSheetAction
  = BottomSheetItemSelected Int32  -- ^ 0-based index of the selected item
  | BottomSheetDismissed           -- ^ The user dismissed the sheet without selecting
  deriving (Show, Eq)

-- | Configuration for a bottom sheet.
data BottomSheetConfig = BottomSheetConfig
  { bscTitle :: Text       -- ^ Sheet title
  , bscItems :: [Text]     -- ^ Selectable item labels
  }

-- | Mutable state for the bottom sheet callback registry.
data BottomSheetState = BottomSheetState
  { bssCallbacks  :: IORef (IntMap (BottomSheetAction -> IO ()))
    -- ^ Map from requestId -> bottom sheet result callback
  , bssNextId     :: IORef Int32
    -- ^ Next available request ID
  , bssContextPtr :: IORef (Ptr ())
    -- ^ Opaque context pointer passed to the C bridge.
    -- Set by 'AppContext.newAppContext' after the 'StablePtr' is created.
  }

-- | Create a fresh 'BottomSheetState' with no pending callbacks.
-- The context pointer is initially null and must be set via
-- 'bssContextPtr' before calling 'showBottomSheet'.
newBottomSheetState :: IO BottomSheetState
newBottomSheetState = do
  callbacks  <- newIORef IntMap.empty
  nextId     <- newIORef 0
  contextPtr <- newIORef nullPtr
  pure BottomSheetState
    { bssCallbacks  = callbacks
    , bssNextId     = nextId
    , bssContextPtr = contextPtr
    }

-- | Convert a C bridge action code to 'BottomSheetAction'.
-- @-1@ is dismissed, @>= 0@ is item index.
-- Returns 'Nothing' for codes @< -1@.
bottomSheetActionFromInt :: CInt -> Maybe BottomSheetAction
bottomSheetActionFromInt (-1) = Just BottomSheetDismissed
bottomSheetActionFromInt code
  | code >= 0 = Just (BottomSheetItemSelected (fromIntegral code))
  | otherwise = Nothing

-- | Show a bottom sheet with the given configuration.  Registers
-- @callback@ and calls the C bridge.  The callback fires when the
-- user taps an item or dismisses the sheet (or synchronously on
-- desktop via the stub that auto-selects the first item).
showBottomSheet :: BottomSheetState -> BottomSheetConfig -> (BottomSheetAction -> IO ()) -> IO ()
showBottomSheet bottomSheetState config callback = do
  requestId <- readIORef (bssNextId bottomSheetState)
  modifyIORef' (bssCallbacks bottomSheetState) (IntMap.insert (fromIntegral requestId) callback)
  writeIORef (bssNextId bottomSheetState) (requestId + 1)
  ctx <- readIORef (bssContextPtr bottomSheetState)
  let joinedItems = Text.unpack (Text.intercalate "\n" (bscItems config))
  withCString (Text.unpack (bscTitle config)) $ \cTitle ->
    withCString joinedItems $ \cItems ->
      c_bottomSheetShow ctx (fromIntegral requestId) cTitle cItems

-- | Dispatch a bottom sheet result from the platform back to the
-- registered Haskell callback.  Removes the callback after firing.
-- Unknown request IDs or action codes are silently logged to stderr.
dispatchBottomSheetResult :: BottomSheetState -> CInt -> CInt -> IO ()
dispatchBottomSheetResult bottomSheetState requestId actionCode =
  case bottomSheetActionFromInt actionCode of
    Nothing -> hPutStrLn stderr $
      "dispatchBottomSheetResult: unknown action code " ++ show actionCode
    Just action -> do
      let reqKey = fromIntegral requestId
      callbacks <- readIORef (bssCallbacks bottomSheetState)
      case IntMap.lookup reqKey callbacks of
        Just callback -> do
          modifyIORef' (bssCallbacks bottomSheetState) (IntMap.delete reqKey)
          callback action
        Nothing -> hPutStrLn stderr $
          "dispatchBottomSheetResult: unknown request ID " ++ show requestId

-- | FFI import: show a bottom sheet via the C bridge.
foreign import ccall "bottom_sheet_show"
  c_bottomSheetShow :: Ptr () -> CInt -> CString -> CString -> IO ()
