module Main where

import Test.Tasty

import Hatter (startMobileApp)
import Hatter.AppContext (AppContext(..), derefAppContext)
import Hatter.Permission (PermissionState)
import Hatter.SecureStorage (SecureStorageState)
import Hatter.Dialog (DialogState)
import Hatter.AuthSession (AuthSessionState)
import Hatter.BottomSheet (BottomSheetState)
import Hatter.Http (HttpState)
import Hatter.PlatformSignIn (PlatformSignInState)
import Test.Helpers (testApp)
import Test.CoreTests (qcProps, unitTests, lifecycleTests, localeTests, i18nTests)
import Test.WidgetTests (uiTests, scrollViewTests, textInputTests, imageTests, webViewTests, mapViewTests, styledTests, textAlignTests, colorTests)
import Test.PlatformTests (permissionTests, secureStorageTests, bleTests, dialogTests, authSessionTests, platformSignInTests, locationTests, bottomSheetTests, cameraTests, httpTests, networkStatusTests)
import Test.AppContextTests (registrationTests, appContextTests, exceptionHandlerTests)
import Test.ActionTests (actionTests, widgetEqTests, incrementalRenderTests)
import Test.AnimationTests (animationTests)
import Test.FilesDirTests (filesDirTests)

main :: IO ()
main = do
  -- Create a single FFI context for permission round-trip tests.
  -- The C desktop stub uses a process-wide g_permission_ctx, so only
  -- one context can be active for FFI permission dispatch.
  ffiCtxPtr <- startMobileApp =<< testApp
  ffiAppCtx <- derefAppContext ffiCtxPtr
  defaultMain (tests
    (acPermissionState ffiAppCtx)
    (acSecureStorageState ffiAppCtx)
    (acDialogState ffiAppCtx)
    (acAuthSessionState ffiAppCtx)
    (acPlatformSignInState ffiAppCtx)
    (acBottomSheetState ffiAppCtx)
    (acHttpState ffiAppCtx))

tests :: PermissionState -> SecureStorageState -> DialogState -> AuthSessionState -> PlatformSignInState -> BottomSheetState -> HttpState -> TestTree
tests ffiPermState ffiSecureStorageState ffiDialogState ffiAuthSessionState ffiPlatformSignInState ffiBottomSheetState ffiHttpState =
  testGroup "Tests"
    [ qcProps
    , unitTests
    , lifecycleTests
    , uiTests
    , scrollViewTests
    , textInputTests
    , imageTests
    , webViewTests
    , mapViewTests
    , styledTests
    , textAlignTests
    , colorTests
    , registrationTests
    , localeTests
    , i18nTests
    , permissionTests ffiPermState
    , secureStorageTests ffiSecureStorageState
    , bleTests
    , dialogTests ffiDialogState
    , locationTests
    , cameraTests
    , authSessionTests ffiAuthSessionState
    , platformSignInTests ffiPlatformSignInState
    , bottomSheetTests ffiBottomSheetState
    , httpTests ffiHttpState
    , networkStatusTests
    , appContextTests
    , exceptionHandlerTests
    , actionTests
    , widgetEqTests
    , incrementalRenderTests
    , animationTests
    , filesDirTests
    ]
