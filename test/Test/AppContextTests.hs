-- | Tests for AppContext registration, lifecycle dispatch, and exception handling.
module Test.AppContextTests
  ( registrationTests
  , appContextTests
  , exceptionHandlerTests
  ) where

import Test.Tasty
import Test.Tasty.HUnit

import Control.Exception (IOException, throwIO, try)
import Data.IORef (newIORef, readIORef, writeIORef, modifyIORef')
import Data.List (isInfixOf)
import HaskellMobile
  ( MobileApp(..)
  , UserState(..)
  , Action(..)
  , createAction
  , newActionState
  , runActionM
  , startMobileApp
  , haskellRenderUI
  , haskellOnUIEvent
  , haskellOnLifecycle
  , freeAppContext
  , derefAppContext
  , AppContext(..)
  )
import HaskellMobile.AppContext (newAppContext)
import HaskellMobile.Lifecycle
  ( LifecycleEvent(..)
  , MobileContext(..)
  , defaultMobileContext
  )
import HaskellMobile.Widget (ButtonConfig(..), TextConfig(..), Widget(..))
import HaskellMobile.Permission (newPermissionState)
import HaskellMobile.SecureStorage (newSecureStorageState)
import HaskellMobile.Ble (newBleState)
import HaskellMobile.Dialog (newDialogState)
import HaskellMobile.Location (newLocationState)
import HaskellMobile.AuthSession (newAuthSessionState)
import HaskellMobile.Camera (newCameraState)
import HaskellMobile.BottomSheet (newBottomSheetState)
import HaskellMobile.Http (newHttpState)
import HaskellMobile.Animation (newAnimationState)
import HaskellMobile.NetworkStatus (newNetworkStatusState)
import Test.Helpers (testApp, viewIsErrorWidget)

-- | Tests for the AppContext-based registration.
-- Each test creates its own context, so no shared global state.
registrationTests :: TestTree
registrationTests = testGroup "Registration"
  [ testCase "startMobileApp returns working context" $ do
      app <- testApp
      ctxPtr <- startMobileApp app
      appCtx <- derefAppContext ctxPtr
      -- Verify the context has a working lifecycle callback
      mapM_ (onLifecycle (acMobileContext appCtx)) [Create, Destroy]
      freeAppContext ctxPtr

  , testCase "view function produces a widget through AppContext" $ do
      actionState <- newActionState
      let customApp = MobileApp
            { maContext     = MobileContext { onLifecycle = \_ -> pure (), onError = \_ -> pure () }
            , maView        = \_userState -> pure (Text TextConfig { tcLabel = "custom", tcFontConfig = Nothing })
            , maActionState = actionState
            }
      ctxPtr <- newAppContext customApp
      appCtx <- derefAppContext ctxPtr
      dummyPermState <- newPermissionState
      dummySecureStorageState <- newSecureStorageState
      dummyBleState  <- newBleState
      dummyDialogState <- newDialogState
      dummyLocationState <- newLocationState
      dummyAuthSessionState <- newAuthSessionState
      dummyCameraState <- newCameraState
      dummyBottomSheetState <- newBottomSheetState
      dummyHttpState <- newHttpState
      dummyNetworkStatusState <- newNetworkStatusState
      dummyAnimationState <- newAnimationState
      let dummyUserState = UserState
            { userPermissionState    = dummyPermState
            , userSecureStorageState = dummySecureStorageState
            , userBleState           = dummyBleState
            , userDialogState        = dummyDialogState
            , userLocationState      = dummyLocationState
            , userAuthSessionState   = dummyAuthSessionState
            , userCameraState        = dummyCameraState
            , userBottomSheetState   = dummyBottomSheetState
            , userHttpState          = dummyHttpState
            , userNetworkStatusState = dummyNetworkStatusState
            , userAnimationState     = dummyAnimationState
            }
      viewFn <- readIORef (acViewFunction appCtx)
      widget <- viewFn dummyUserState
      case widget of
        Text config -> tcLabel config @?= "custom"
        _           -> assertFailure "expected Text \"custom\""
      freeAppContext ctxPtr

  , testCase "two contexts are independent" $ do
      actionStateA <- newActionState
      actionStateB <- newActionState
      let appA = MobileApp
            { maContext     = defaultMobileContext
            , maView        = \_userState -> pure (Text TextConfig { tcLabel = "A", tcFontConfig = Nothing })
            , maActionState = actionStateA
            }
          appB = MobileApp
            { maContext     = defaultMobileContext
            , maView        = \_userState -> pure (Text TextConfig { tcLabel = "B", tcFontConfig = Nothing })
            , maActionState = actionStateB
            }
      ctxPtrA <- newAppContext appA
      ctxPtrB <- newAppContext appB
      appCtxA <- derefAppContext ctxPtrA
      appCtxB <- derefAppContext ctxPtrB
      dummyPermState <- newPermissionState
      dummySecureStorageState <- newSecureStorageState
      dummyBleState  <- newBleState
      dummyDialogState <- newDialogState
      dummyLocationState <- newLocationState
      dummyAuthSessionState <- newAuthSessionState
      dummyCameraState <- newCameraState
      dummyBottomSheetState <- newBottomSheetState
      dummyHttpState <- newHttpState
      dummyNetworkStatusState <- newNetworkStatusState
      dummyAnimationState <- newAnimationState
      let dummyUserState = UserState
            { userPermissionState    = dummyPermState
            , userSecureStorageState = dummySecureStorageState
            , userBleState           = dummyBleState
            , userDialogState        = dummyDialogState
            , userLocationState      = dummyLocationState
            , userAuthSessionState   = dummyAuthSessionState
            , userCameraState        = dummyCameraState
            , userBottomSheetState   = dummyBottomSheetState
            , userHttpState          = dummyHttpState
            , userNetworkStatusState = dummyNetworkStatusState
            , userAnimationState     = dummyAnimationState
            }
      viewFnA <- readIORef (acViewFunction appCtxA)
      viewFnB <- readIORef (acViewFunction appCtxB)
      widgetA <- viewFnA dummyUserState
      widgetB <- viewFnB dummyUserState
      case widgetA of
        Text config -> tcLabel config @?= "A"
        _           -> assertFailure "expected Text \"A\""
      case widgetB of
        Text config -> tcLabel config @?= "B"
        _           -> assertFailure "expected Text \"B\""
      freeAppContext ctxPtrA
      freeAppContext ctxPtrB
  ]

appContextTests :: TestTree
appContextTests = testGroup "AppContext"
  [ testCase "newAppContext produces working lifecycle context" $ do
      ref <- newIORef ([] :: [LifecycleEvent])
      actionState <- newActionState
      let app = MobileApp
            { maContext     = MobileContext { onLifecycle = \event -> modifyIORef' ref (++ [event]), onError = \_ -> pure () }
            , maView        = \_userState -> pure (Text TextConfig { tcLabel = "dummy", tcFontConfig = Nothing })
            , maActionState = actionState
            }
      ctxPtr <- newAppContext app
      haskellOnLifecycle ctxPtr 0  -- Create
      haskellOnLifecycle ctxPtr 2  -- Resume
      haskellOnLifecycle ctxPtr 5  -- Destroy
      freeAppContext ctxPtr
      received <- readIORef ref
      received @?= [Create, Resume, Destroy]
  ]

-- | Tests for the default exception handler that wraps FFI entry points.
-- Each test creates its own context, so no shared global mutation.
exceptionHandlerTests :: TestTree
exceptionHandlerTests = testGroup "ExceptionHandler"
  [ testCase "exception in view is caught and view replaced with error widget" $ do
      actionState <- newActionState
      let crashingApp = MobileApp
            { maContext     = defaultMobileContext
            , maView        = \_userState -> throwIO (userError "test-boom")
            , maActionState = actionState
            }
      ctxPtr <- newAppContext crashingApp
      haskellRenderUI ctxPtr
      isError <- viewIsErrorWidget ctxPtr
      assertBool "view should be replaced with error widget" isError
      freeAppContext ctxPtr

  , testCase "exception in button callback is caught" $ do
      actionState <- newActionState
      crashHandle <- runActionM actionState $
        createAction (throwIO (userError "button-boom"))
      let crashingApp = MobileApp
            { maContext     = defaultMobileContext
            , maView        = \_userState -> pure $ Button ButtonConfig
                { bcLabel  = "crash"
                , bcAction = crashHandle
                , bcFontConfig = Nothing
                }
            , maActionState = actionState
            }
      ctxPtr <- newAppContext crashingApp
      -- First render to register the button callback
      haskellRenderUI ctxPtr
      -- Dispatch the button, which throws — handler overwrites view
      haskellOnUIEvent ctxPtr (fromIntegral (actionId crashHandle))
      isError <- viewIsErrorWidget ctxPtr
      assertBool "view should be error widget after button callback exception" isError
      freeAppContext ctxPtr

  , testCase "dismiss restores original view after transient error" $ do
      -- Transient error: throws once, then succeeds
      shouldThrow <- newIORef True
      actionState <- newActionState
      let transientView _userState = do
            throwing <- readIORef shouldThrow
            if throwing
              then do
                writeIORef shouldThrow False
                throwIO (userError "transient-error")
              else pure $ Text TextConfig { tcLabel = "recovered", tcFontConfig = Nothing }
          transientApp = MobileApp
            { maContext     = defaultMobileContext
            , maView        = transientView
            , maActionState = actionState
            }
      ctxPtr <- newAppContext transientApp
      -- First render throws, error widget shown, flag cleared
      haskellRenderUI ctxPtr
      isError <- viewIsErrorWidget ctxPtr
      assertBool "should show error widget" isError
      -- Dispatch the dismiss action (pre-registered during newAppContext).
      appCtx <- derefAppContext ctxPtr
      let dismissId = actionId (acDismissAction appCtx)
      haskellOnUIEvent ctxPtr (fromIntegral dismissId)
      isStillError <- viewIsErrorWidget ctxPtr
      assertBool "should no longer show error widget after dismiss" (not isStillError)
      freeAppContext ctxPtr

  , testCase "onError callback fires on exception" $ do
      ref <- newIORef (Nothing :: Maybe String)
      actionState <- newActionState
      let ctx = MobileContext
            { onLifecycle = \_ -> pure ()
            , onError     = \exc -> writeIORef ref (Just (show exc))
            }
          crashingApp = MobileApp
            { maContext     = ctx
            , maView        = \_userState -> throwIO (userError "onError-test")
            , maActionState = actionState
            }
      ctxPtr <- newAppContext crashingApp
      haskellRenderUI ctxPtr
      firedValue <- readIORef ref
      case firedValue of
        Nothing  -> assertFailure "onError callback should have been fired"
        Just msg -> assertBool "onError should receive the exception" ("onError-test" `isInfixOf` msg)
      freeAppContext ctxPtr

  , testCase "exception in onError does not crash" $ do
      actionState <- newActionState
      let ctx = MobileContext
            { onLifecycle = \_ -> pure ()
            , onError     = \_ -> throwIO (userError "secondary-boom")
            }
          crashingApp = MobileApp
            { maContext     = ctx
            , maView        = \_userState -> throwIO (userError "primary-boom")
            , maActionState = actionState
            }
      ctxPtr <- newAppContext crashingApp
      -- Should not crash despite both view and onError throwing
      result <- try @IOException (haskellRenderUI ctxPtr)
      case result of
        Left exc -> assertFailure ("haskellRenderUI should not throw, but got: " ++ show exc)
        Right () -> pure ()
      freeAppContext ctxPtr

  , testCase "exception in lifecycle handler is caught" $ do
      actionState <- newActionState
      let crashingApp = MobileApp
            { maContext     = MobileContext
                { onLifecycle = \_ -> throwIO (userError "lifecycle-boom")
                , onError     = \_ -> pure ()
                }
            , maView        = \_userState -> pure (Text TextConfig { tcLabel = "dummy", tcFontConfig = Nothing })
            , maActionState = actionState
            }
      ctxPtr <- newAppContext crashingApp
      result <- try @IOException (haskellOnLifecycle ctxPtr 0)
      case result of
        Left exc -> assertFailure ("haskellOnLifecycle should not throw, but got: " ++ show exc)
        Right () -> pure ()
      freeAppContext ctxPtr
  ]
