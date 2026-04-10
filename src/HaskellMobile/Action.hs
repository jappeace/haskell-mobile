{-# LANGUAGE ImportQualifiedPost #-}
-- | Opaque callback handles for the widget system.
--
-- Instead of embedding raw @IO ()@ closures inside widget configs,
-- the framework uses typed handles ('Action', 'OnChange') that
-- reference entries in a shared 'ActionState' registry.  Because
-- the handles are plain 'Int32' newtypes they derive 'Eq', which
-- lets 'Widget' derive 'Eq' naturally — enabling O(1) "skip if
-- unchanged" diff in the render engine.
--
-- Users create handles once at init time via the restricted 'ActionM'
-- monad, then embed them in widget configs.  The callback 'IntMap's
-- are never cleared during rendering, eliminating the atomicity gap
-- of the old clear-and-rebuild strategy.
module HaskellMobile.Action
  ( -- * Handles
    Action(..)
  , OnChange(..)
    -- * Callback registry
  , ActionState(..)
    -- * Restricted construction monad
  , ActionM
  , createAction
  , createOnChange
  , liftIO
    -- * Framework-internal
  , newActionState
  , runActionM
  , lookupAction
  , lookupTextAction
  )
where

import Data.IORef (IORef, newIORef, readIORef, modifyIORef')
import Data.Int (Int32)
import Data.IntMap.Strict (IntMap)
import Data.IntMap.Strict qualified as IntMap
import Data.Text (Text)

-- | An opaque handle to a click / tap callback.
-- Carries only an 'Int32' identifier, so it derives 'Eq' and 'Show'.
newtype Action = Action { actionId :: Int32 }
  deriving (Eq, Show)

-- | An opaque handle to a text-change callback.
-- Carries only an 'Int32' identifier, so it derives 'Eq' and 'Show'.
newtype OnChange = OnChange { onChangeId :: Int32 }
  deriving (Eq, Show)

-- | Mutable callback storage shared between 'ActionM' (creation)
-- and the render/dispatch engine (lookup).
data ActionState = ActionState
  { asCallbacks     :: IORef (IntMap (IO ()))
    -- ^ Click/tap callbacks keyed by handle ID.
  , asTextCallbacks :: IORef (IntMap (Text -> IO ()))
    -- ^ Text-change callbacks keyed by handle ID.
  , asNextId        :: IORef Int32
    -- ^ Monotonically increasing counter for the next handle ID.
  }

-- | Create a fresh empty 'ActionState'.
newActionState :: IO ActionState
newActionState = do
  callbacks     <- newIORef IntMap.empty
  textCallbacks <- newIORef IntMap.empty
  nextId        <- newIORef 0
  pure ActionState
    { asCallbacks     = callbacks
    , asTextCallbacks = textCallbacks
    , asNextId        = nextId
    }

-- | A restricted monad for creating callback handles.
-- The constructor is hidden so that users cannot construct arbitrary
-- 'ActionM' values — they must go through 'createAction' and
-- 'createOnChange'.
newtype ActionM a = ActionM { unActionM :: ActionState -> IO a }

instance Functor ActionM where
  fmap f (ActionM g) = ActionM (\state -> fmap f (g state))

instance Applicative ActionM where
  pure x = ActionM (\_state -> pure x)
  ActionM mf <*> ActionM mx = ActionM (\state -> mf state <*> mx state)

instance Monad ActionM where
  ActionM mx >>= f = ActionM (\state -> do
    x <- mx state
    unActionM (f x) state)

-- | Lift an arbitrary 'IO' action into 'ActionM'.
-- Useful for creating 'IORef's in init blocks.
liftIO :: IO a -> ActionM a
liftIO action = ActionM (\_state -> action)

-- | Register a click/tap callback and return its opaque handle.
createAction :: IO () -> ActionM Action
createAction callback = ActionM $ \state -> do
  handleId <- readIORef (asNextId state)
  modifyIORef' (asCallbacks state) (IntMap.insert (fromIntegral handleId) callback)
  modifyIORef' (asNextId state) (+ 1)
  pure (Action handleId)

-- | Register a text-change callback and return its opaque handle.
createOnChange :: (Text -> IO ()) -> ActionM OnChange
createOnChange callback = ActionM $ \state -> do
  handleId <- readIORef (asNextId state)
  modifyIORef' (asTextCallbacks state) (IntMap.insert (fromIntegral handleId) callback)
  modifyIORef' (asNextId state) (+ 1)
  pure (OnChange handleId)

-- | Run an 'ActionM' computation against a given 'ActionState'.
runActionM :: ActionState -> ActionM a -> IO a
runActionM state (ActionM f) = f state

-- | Look up a click/tap callback by handle ID.
-- Returns 'Nothing' if the ID is not registered.
lookupAction :: ActionState -> Int32 -> IO (Maybe (IO ()))
lookupAction state handleId = do
  callbacks <- readIORef (asCallbacks state)
  pure (IntMap.lookup (fromIntegral handleId) callbacks)

-- | Look up a text-change callback by handle ID.
-- Returns 'Nothing' if the ID is not registered.
lookupTextAction :: ActionState -> Int32 -> IO (Maybe (Text -> IO ()))
lookupTextAction state handleId = do
  callbacks <- readIORef (asTextCallbacks state)
  pure (IntMap.lookup (fromIntegral handleId) callbacks)
