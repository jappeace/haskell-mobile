-- | Shared test helpers used across multiple test modules.
module Test.Helpers
  ( withActions
  , withAppContext
  , withContext
  , makeDummyApp
  , makeSimpleApp
  , testApp
  , viewIsErrorWidget
  , oneTwoThree
  ) where

import Data.IORef (readIORef)
import Foreign.Ptr (Ptr)
import HaskellMobile
  ( MobileApp(..)
  , UserState(..)
  , ActionM
  , newActionState
  , runActionM
  , freeAppContext
  , derefAppContext
  , AppContext(..)
  )
import HaskellMobile.AppContext (newAppContext)
import HaskellMobile.Lifecycle
  ( LifecycleEvent(..)
  , MobileContext(..)
  , defaultMobileContext
  , loggingMobileContext
  )
import HaskellMobile.Widget (TextConfig(..), Widget(..))
import HaskellMobile.Render (RenderState, newRenderState)

-- | Helper: create an ActionState, register actions via ActionM, and
-- build a RenderState.  Returns the registered value together with the
-- RenderState so tests can dispatch by handle ID.
withActions :: ActionM a -> IO (a, RenderState)
withActions actionM = do
  actionState <- newActionState
  result <- runActionM actionState actionM
  rs <- newRenderState actionState
  pure (result, rs)

-- | Helper: create an 'AppContext' from a 'MobileApp',
-- run an action with the typed 'Ptr AppContext', then free the context.
withAppContext :: MobileApp -> (Ptr AppContext -> IO a) -> IO a
withAppContext app action = do
  ptr <- newAppContext app
  result <- action ptr
  freeAppContext ptr
  pure result

-- | Helper: create an 'AppContext' with the given lifecycle callback,
-- run an action with the typed 'Ptr AppContext', then free the context.
withContext :: (LifecycleEvent -> IO ()) -> (Ptr AppContext -> IO a) -> IO a
withContext callback action = do
  dummyApp <- makeDummyApp callback
  withAppContext dummyApp action

-- | Create a dummy MobileApp with the given lifecycle callback.
makeDummyApp :: (LifecycleEvent -> IO ()) -> IO MobileApp
makeDummyApp callback = do
  actionState <- newActionState
  pure MobileApp
    { maContext     = MobileContext { onLifecycle = callback, onError = \_ -> pure () }
    , maView        = \_userState -> pure (Text TextConfig { tcLabel = "dummy", tcFontConfig = Nothing })
    , maActionState = actionState
    }

-- | Helper: make a simple MobileApp with default context.
makeSimpleApp :: (UserState -> IO Widget) -> IO MobileApp
makeSimpleApp viewFn = do
  actionState <- newActionState
  pure MobileApp
    { maContext     = defaultMobileContext
    , maView        = viewFn
    , maActionState = actionState
    }

-- | Trivial test app with loggingMobileContext and a simple Text view.
testApp :: IO MobileApp
testApp = do
  actionState <- newActionState
  pure MobileApp
    { maContext     = loggingMobileContext
    , maView        = \_userState -> pure (Text TextConfig { tcLabel = "test", tcFontConfig = Nothing })
    , maActionState = actionState
    }

oneTwoThree :: [Int]
oneTwoThree = [1, 2, 3]

-- | Helper: check whether the context's view function produces an error widget
-- (a Column whose first child is a Text with "An error occurred").
viewIsErrorWidget :: Ptr AppContext -> IO Bool
viewIsErrorWidget ctxPtr = do
  appCtx <- derefAppContext ctxPtr
  viewFn <- readIORef (acViewFunction appCtx)
  let userState = UserState
        { userPermissionState    = acPermissionState appCtx
        , userSecureStorageState = acSecureStorageState appCtx
        , userBleState           = acBleState appCtx
        , userDialogState        = acDialogState appCtx
        , userLocationState      = acLocationState appCtx
        , userAuthSessionState   = acAuthSessionState appCtx
        , userCameraState        = acCameraState appCtx
        , userBottomSheetState   = acBottomSheetState appCtx
        , userHttpState          = acHttpState appCtx
        , userNetworkStatusState = acNetworkStatusState appCtx
        }
  widget <- viewFn userState
  case widget of
    Column (Text config : _) -> pure (tcLabel config == "An error occurred")
    Column _                 -> pure False
    Text _                   -> pure False
    Button _                 -> pure False
    TextInput _              -> pure False
    Image _                  -> pure False
    WebView _                -> pure False
    MapView _                -> pure False
    Row _                    -> pure False
    ScrollView _             -> pure False
    Styled _ _               -> pure False
