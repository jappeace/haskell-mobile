{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE ImportQualifiedPost #-}
-- | Modal dialog / alert API for mobile platforms.
--
-- Provides an imperative API for showing platform-native modal dialogs
-- (Android AlertDialog, iOS UIAlertController, watchOS SwiftUI .alert).
-- Dialogs are fire-and-forget: the platform manages the dialog lifecycle
-- independently of the Haskell UI rendering loop.
--
-- The callback registry follows the same sequential 'IORef' 'Int32'
-- pattern used by "Hatter.SecureStorage" and "Hatter.Permission".
-- Up to 3 buttons are supported (Android AlertDialog's maximum).
module Hatter.Dialog
  ( DialogAction(..)
  , DialogConfig(..)
  , DialogState(..)
  , newDialogState
  , dialogActionFromInt
  , showDialog
  , dispatchDialogResult
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

-- | Which button was tapped, or whether the dialog was dismissed.
data DialogAction
  = DialogButton1
  | DialogButton2
  | DialogButton3
  | DialogDismissed
  deriving (Show, Eq, Ord, Enum, Bounded)

-- | Configuration for a dialog.  At least one button ('dcButton1') is
-- required.  The second and third buttons are optional.
data DialogConfig = DialogConfig
  { dcTitle   :: Text
  , dcMessage :: Text
  , dcButton1 :: Text
  , dcButton2 :: Maybe Text
  , dcButton3 :: Maybe Text
  }

-- | Mutable state for the dialog callback registry.
data DialogState = DialogState
  { dsCallbacks  :: IORef (IntMap (DialogAction -> IO ()))
    -- ^ Map from requestId -> dialog result callback
  , dsNextId     :: IORef Int32
    -- ^ Next available request ID
  , dsContextPtr :: IORef (Ptr ())
    -- ^ Opaque context pointer passed to the C bridge.
    -- Set by 'AppContext.newAppContext' after the 'StablePtr' is created.
  }

-- | Create a fresh 'DialogState' with no pending callbacks.
-- The context pointer is initially null and must be set via
-- 'dsContextPtr' before calling 'showDialog'.
newDialogState :: IO DialogState
newDialogState = do
  callbacks  <- newIORef IntMap.empty
  nextId     <- newIORef 0
  contextPtr <- newIORef nullPtr
  pure DialogState
    { dsCallbacks  = callbacks
    , dsNextId     = nextId
    , dsContextPtr = contextPtr
    }

-- | Convert a C bridge action code to 'DialogAction'.
-- Returns 'Nothing' for unknown codes.
dialogActionFromInt :: CInt -> Maybe DialogAction
dialogActionFromInt 0 = Just DialogButton1
dialogActionFromInt 1 = Just DialogButton2
dialogActionFromInt 2 = Just DialogButton3
dialogActionFromInt 3 = Just DialogDismissed
dialogActionFromInt _ = Nothing

-- | Show a modal dialog with the given configuration.  Registers
-- @callback@ and calls the C bridge.  The callback fires when the
-- user taps a button or dismisses the dialog (or synchronously on
-- desktop via the stub that auto-presses button 1).
showDialog :: DialogState -> DialogConfig -> (DialogAction -> IO ()) -> IO ()
showDialog dialogState config callback = do
  requestId <- readIORef (dsNextId dialogState)
  modifyIORef' (dsCallbacks dialogState) (IntMap.insert (fromIntegral requestId) callback)
  writeIORef (dsNextId dialogState) (requestId + 1)
  ctx <- readIORef (dsContextPtr dialogState)
  withCString (Text.unpack (dcTitle config)) $ \cTitle ->
    withCString (Text.unpack (dcMessage config)) $ \cMessage ->
      withCString (Text.unpack (dcButton1 config)) $ \cButton1 ->
        withOptionalCString (dcButton2 config) $ \cButton2 ->
          withOptionalCString (dcButton3 config) $ \cButton3 ->
            c_dialogShow ctx (fromIntegral requestId) cTitle cMessage cButton1 cButton2 cButton3

-- | Dispatch a dialog result from the platform back to the
-- registered Haskell callback.  Removes the callback after firing.
-- Unknown request IDs or action codes are silently logged to stderr.
dispatchDialogResult :: DialogState -> CInt -> CInt -> IO ()
dispatchDialogResult dialogState requestId actionCode =
  case dialogActionFromInt actionCode of
    Nothing -> hPutStrLn stderr $
      "dispatchDialogResult: unknown action code " ++ show actionCode
    Just action -> do
      let reqKey = fromIntegral requestId
      callbacks <- readIORef (dsCallbacks dialogState)
      case IntMap.lookup reqKey callbacks of
        Just callback -> do
          modifyIORef' (dsCallbacks dialogState) (IntMap.delete reqKey)
          callback action
        Nothing -> hPutStrLn stderr $
          "dispatchDialogResult: unknown request ID " ++ show requestId

-- | Helper: call a continuation with a CString or nullPtr.
withOptionalCString :: Maybe Text -> (CString -> IO a) -> IO a
withOptionalCString Nothing  action = action nullPtr
withOptionalCString (Just t) action = withCString (Text.unpack t) action

-- | FFI import: show a dialog via the C bridge.
foreign import ccall "dialog_show"
  c_dialogShow :: Ptr () -> CInt -> CString -> CString -> CString -> CString -> CString -> IO ()
