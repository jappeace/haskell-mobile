module Main where

import Test.Tasty

import HaskellMobile (startMobileApp, derefAppContext, AppContext(..))
import HaskellMobile.Permission (PermissionState)
import HaskellMobile.SecureStorage (SecureStorageState)
import HaskellMobile.Dialog (DialogState)
import HaskellMobile.AuthSession (AuthSessionState)
import HaskellMobile.BottomSheet (BottomSheetState)
import HaskellMobile.Http (HttpState)
import Test.Helpers (testApp)
import Test.CoreTests (qcProps, unitTests, lifecycleTests, localeTests, i18nTests)
import Test.WidgetTests (uiTests, scrollViewTests, textInputTests, imageTests, webViewTests, mapViewTests, styledTests, textAlignTests, colorTests)
import Test.PlatformTests (permissionTests, secureStorageTests, bleTests, dialogTests, authSessionTests, locationTests, bottomSheetTests, cameraTests, httpTests, networkStatusTests)
import Test.AppContextTests (registrationTests, appContextTests, exceptionHandlerTests)
import Test.ActionTests (actionTests, widgetEqTests, incrementalRenderTests)

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
    (acBottomSheetState ffiAppCtx)
    (acHttpState ffiAppCtx))

tests :: PermissionState -> SecureStorageState -> DialogState -> AuthSessionState -> BottomSheetState -> HttpState -> TestTree
tests ffiPermState ffiSecureStorageState ffiDialogState ffiAuthSessionState ffiBottomSheetState ffiHttpState =
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
    , bottomSheetTests ffiBottomSheetState
    , httpTests ffiHttpState
    , networkStatusTests
    , appContextTests
    , exceptionHandlerTests
    , actionTests
    , widgetEqTests
    , incrementalRenderTests
    ]
