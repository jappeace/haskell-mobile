module Main where

import Test.Tasty
import Test.Tasty.QuickCheck as QC
import Test.Tasty.HUnit

import Data.ByteString qualified as BS
import Data.Either (isLeft)
import Data.List (isInfixOf, sort)
import Data.IntMap.Strict qualified as IntMap
import Control.Exception (IOException, throwIO, try)
import Data.IORef (newIORef, readIORef, modifyIORef', writeIORef)
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import Foreign.C.String (newCString, peekCString)
import Foreign.Marshal.Alloc (free)
import Foreign.Ptr (Ptr, nullPtr)
import HaskellMobile
  ( MobileApp(..)
  , UserState(..)
  , startMobileApp
  , haskellGreet
  , haskellRenderUI
  , haskellOnUIEvent
  , haskellOnLifecycle
  , freeAppContext
  , derefAppContext
  , AppContext(..)
  )
import HaskellMobile.AppContext (newAppContext)
import HaskellMobile.Locale
  ( Language(..)
  , Locale(..)
  , LocaleFailure(..)
  , getSystemLocale
  , parseLocale
  , localeToText
  )
import HaskellMobile.I18n
  ( Key(..)
  , TranslateFailure(..)
  , translate
  )
import HaskellMobile.App (mobileApp)
import HaskellMobile.Lifecycle
  ( LifecycleEvent(..)
  , MobileContext(..)
  , defaultMobileContext
  , lifecycleFromInt
  , lifecycleToInt
  , loggingMobileContext
  )
import HaskellMobile.Widget (ButtonConfig(..), Color(..), FontConfig(..), ImageConfig(..), ImageSource(..), InputType(..), ResourceName(..), ScaleType(..), TextAlignment(..), TextConfig(..), TextInputConfig(..), WebViewConfig(..), Widget(..), WidgetStyle(..), colorFromText, colorToHex, defaultStyle)
import HaskellMobile.Permission
  ( Permission(..)
  , PermissionStatus(..)
  , PermissionState(..)
  , newPermissionState
  , requestPermission
  , checkPermission
  , dispatchPermissionResult
  , permissionToInt
  , permissionStatusFromInt
  )
import HaskellMobile.Ble
  ( BleAdapterStatus(..)
  , BleScanResult(..)
  , BleState(..)
  , newBleState
  , bleAdapterStatusFromInt
  , bleAdapterStatusToInt
  , checkBleAdapter
  , startBleScan
  , stopBleScan
  , dispatchBleScanResult
  )
import HaskellMobile.Location
  ( LocationData(..)
  , LocationState(..)
  , newLocationState
  , startLocationUpdates
  , stopLocationUpdates
  , dispatchLocationUpdate
  )
import HaskellMobile.Camera
  ( CameraSource(..)
  , CameraStatus(..)
  , CameraResult(..)
  , CameraState(..)
  , newCameraState
  , cameraSourceToInt
  , cameraStatusFromInt
  , capturePhoto
  , startVideoCapture
  , stopCameraSession
  , dispatchCameraResult
  )
import HaskellMobile.Render (newRenderState, renderWidget, dispatchEvent, dispatchTextEvent)
import HaskellMobile.SecureStorage
  ( SecureStorageStatus(..)
  , SecureStorageState(..)
  , newSecureStorageState
  , secureStorageWrite
  , secureStorageRead
  , secureStorageDelete
  , dispatchSecureStorageResult
  , storageStatusFromInt
  )
import HaskellMobile.Dialog
  ( DialogAction(..)
  , DialogConfig(..)
  , DialogState(..)
  , newDialogState
  , showDialog
  , dispatchDialogResult
  , dialogActionFromInt
  )
import HaskellMobile.AuthSession
  ( AuthSessionResult(..)
  , AuthSessionState(..)
  , newAuthSessionState
  , startAuthSession
  , dispatchAuthSessionResult
  , authSessionResultFromInt
  )

main :: IO ()
main = do
  -- Create a single FFI context for permission round-trip tests.
  -- The C desktop stub uses a process-wide g_permission_ctx, so only
  -- one context can be active for FFI permission dispatch.
  ffiCtxPtr <- startMobileApp mobileApp
  ffiAppCtx <- derefAppContext ffiCtxPtr
  defaultMain (tests (acPermissionState ffiAppCtx) (acSecureStorageState ffiAppCtx) (acDialogState ffiAppCtx) (acAuthSessionState ffiAppCtx))

tests :: PermissionState -> SecureStorageState -> DialogState -> AuthSessionState -> TestTree
tests ffiPermState ffiSecureStorageState ffiDialogState ffiAuthSessionState = testGroup "Tests" [qcProps, unitTests, lifecycleTests, uiTests, scrollViewTests, textInputTests, imageTests, webViewTests, styledTests, textAlignTests, colorTests, registrationTests, localeTests, i18nTests, permissionTests ffiPermState, secureStorageTests ffiSecureStorageState, bleTests, dialogTests ffiDialogState, locationTests, cameraTests, authSessionTests ffiAuthSessionState, appContextTests, exceptionHandlerTests]

qcProps :: TestTree
qcProps = testGroup "(checked by QuickCheck)"
  [ QC.testProperty "sort == sort . reverse" $
      \list -> sort (list :: [Int]) == sort (reverse list)
  , QC.testProperty "Fermat's little theorem" $
      \x -> ((x :: Integer)^zeven  - x) `mod` zeven == 0
  ]
  where
    zeven :: Integer
    zeven = 7

oneTwoThree :: [Int]
oneTwoThree = [1, 2, 3]

unitTests :: TestTree
unitTests = testGroup "Unit tests"
  [ testCase "List comparison (different length)" $
       oneTwoThree `compare` [1,2] @?= GT

  -- the following test does not hold
  , testCase "List comparison (same length)" $
      oneTwoThree `compare` [1,2,3] @?= EQ
  , testCase "haskellGreet returns correct greeting" $ do
      cname <- newCString "World"
      cresult <- haskellGreet cname
      result <- peekCString cresult
      free cresult
      free cname
      result @?= "Hello from Haskell, World!"
  , testCase "haskellGreet with different input" $ do
      cname <- newCString "Android"
      cresult <- haskellGreet cname
      result <- peekCString cresult
      free cresult
      free cname
      result @?= "Hello from Haskell, Android!"
  ]

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
withContext callback action = withAppContext dummyApp action
  where
    dummyApp = MobileApp
      { maContext = MobileContext { onLifecycle = callback, onError = \_ -> pure () }
      , maView    = \_userState -> pure (Text TextConfig { tcLabel = "dummy", tcFontConfig = Nothing })
      }

allEvents :: [LifecycleEvent]
allEvents = [Create, Start, Resume, Pause, Stop, Destroy, LowMemory]

lifecycleTests :: TestTree
lifecycleTests = testGroup "Lifecycle"
  [ testCase "lifecycleToInt produces sequential codes 0-6" $
      map lifecycleToInt allEvents @?= [0, 1, 2, 3, 4, 5, 6]
  , testCase "lifecycleFromInt roundtrips for all events" $
      mapM_ (\event ->
        lifecycleFromInt (lifecycleToInt event) @?= Just event
      ) allEvents
  , testCase "lifecycleFromInt returns Nothing for unknown codes" $ do
      lifecycleFromInt 7 @?= Nothing
      lifecycleFromInt (-1) @?= Nothing
      lifecycleFromInt 100 @?= Nothing
  , testCase "callback receives dispatched event" $ do
      ref <- newIORef ([] :: [LifecycleEvent])
      withContext (\event -> modifyIORef' ref (++ [event])) $ \ctx ->
        haskellOnLifecycle ctx 2
      received <- readIORef ref
      received @?= [Resume]
  , testCase "unknown codes are silently ignored" $ do
      ref <- newIORef (0 :: Int)
      withContext (\_ -> modifyIORef' ref (+ 1)) $ \ctx -> do
        haskellOnLifecycle ctx 99
        haskellOnLifecycle ctx (-1)
      count <- readIORef ref
      count @?= 0
  , testCase "all 7 event types received in order" $ do
      ref <- newIORef ([] :: [LifecycleEvent])
      withContext (\event -> modifyIORef' ref (++ [event])) $ \ctx ->
        mapM_ (haskellOnLifecycle ctx . lifecycleToInt) allEvents
      received <- readIORef ref
      received @?= allEvents
  , testCase "loggingMobileContext handles all events without throwing" $
      mapM_ (onLifecycle loggingMobileContext) allEvents
  , testCase "mobileApp context handles all events without throwing" $
      mapM_ (onLifecycle (maContext mobileApp)) allEvents
  ]

uiTests :: TestTree
uiTests = testGroup "UI"
  [ testCase "callback dispatch fires registered action" $ do
      ref <- newIORef (0 :: Int)
      rs <- newRenderState
      let widget = Button ButtonConfig
            { bcLabel = "click me", bcAction = modifyIORef' ref (+ 1), bcFontConfig = Nothing }
      renderWidget rs widget
      -- After rendering, callback 0 should be the button's handler
      dispatchEvent rs 0
      count <- readIORef ref
      count @?= 1

  , testCase "multiple callbacks each fire independently" $ do
      refA <- newIORef False
      refB <- newIORef False
      rs <- newRenderState
      let widget = Row
            [ Button ButtonConfig
                { bcLabel = "A", bcAction = modifyIORef' refA (const True), bcFontConfig = Nothing }
            , Button ButtonConfig
                { bcLabel = "B", bcAction = modifyIORef' refB (const True), bcFontConfig = Nothing }
            ]
      renderWidget rs widget
      -- Only fire callback 0 (button A)
      dispatchEvent rs 0
      a <- readIORef refA
      b <- readIORef refB
      a @?= True
      b @?= False
      -- Now fire callback 1 (button B)
      dispatchEvent rs 1
      b' <- readIORef refB
      b' @?= True

  , testCase "re-render resets callback IDs" $ do
      refOld <- newIORef False
      refNew <- newIORef False
      rs <- newRenderState
      -- First render with old callback
      renderWidget rs (Button ButtonConfig
        { bcLabel = "old", bcAction = modifyIORef' refOld (const True), bcFontConfig = Nothing })
      -- Second render replaces it
      renderWidget rs (Button ButtonConfig
        { bcLabel = "new", bcAction = modifyIORef' refNew (const True), bcFontConfig = Nothing })
      dispatchEvent rs 0
      old <- readIORef refOld
      new <- readIORef refNew
      old @?= False
      new @?= True

  , testCase "dispatching unknown callback ID logs error" $ do
      rs <- newRenderState
      renderWidget rs (Text TextConfig { tcLabel = "no buttons", tcFontConfig = Nothing })
      -- Should not throw (logs to stderr)
      dispatchEvent rs 42
      dispatchEvent rs 999

  , testCase "nested widget tree renders without error" $ do
      rs <- newRenderState
      let widget = Column
            [ Text TextConfig { tcLabel = "header", tcFontConfig = Nothing }
            , Row
              [ Button ButtonConfig
                  { bcLabel = "a", bcAction = pure (), bcFontConfig = Nothing }
              , Column
                [ Text TextConfig { tcLabel = "nested", tcFontConfig = Nothing }
                , Button ButtonConfig
                    { bcLabel = "b", bcAction = pure (), bcFontConfig = Nothing }
                ]
              ]
            , Text TextConfig { tcLabel = "footer", tcFontConfig = Nothing }
            ]
      -- Should not throw — exercises all node types
      renderWidget rs widget

  , testCase "mobileApp view returns a widget" $ do
      dummyPermState <- newPermissionState
      dummySecureStorageState <- newSecureStorageState
      dummyBleState  <- newBleState
      dummyDialogState <- newDialogState
      dummyLocationState <- newLocationState
      dummyAuthSessionState <- newAuthSessionState
      dummyCameraState <- newCameraState
      let dummyUserState = UserState
            { userPermissionState    = dummyPermState
            , userSecureStorageState = dummySecureStorageState
            , userBleState           = dummyBleState
            , userDialogState        = dummyDialogState
            , userLocationState      = dummyLocationState
            , userAuthSessionState   = dummyAuthSessionState
            , userCameraState        = dummyCameraState
            }
      widget <- maView mobileApp dummyUserState
      -- mobileApp is the counter demo; verify it's a column
      case widget of
        Column _        -> pure ()
        Text _          -> assertFailure "expected Column, got Text"
        Button _        -> assertFailure "expected Column, got Button"
        TextInput _     -> assertFailure "expected Column, got TextInput"
        Image _         -> assertFailure "expected Column, got Image"
        WebView _       -> assertFailure "expected Column, got WebView"
        Row _           -> assertFailure "expected Column, got Row"
        ScrollView _    -> assertFailure "expected Column, got ScrollView"
        CameraView _    -> assertFailure "expected Column, got CameraView"
        Styled _ _      -> assertFailure "expected Column, got Styled"
  ]

-- | Tests for the ScrollView widget binding.
-- These exercise the Haskell render path shared by both Android and iOS —
-- the platform bridge (JNI / UIKit) receives UI_NODE_SCROLL_VIEW (5) and
-- is responsible for mapping it to a native scroll container.
scrollViewTests :: TestTree
scrollViewTests = testGroup "ScrollView"
  [ testCase "ScrollView renders without error" $ do
      rs <- newRenderState
      renderWidget rs (ScrollView
        [ Text TextConfig { tcLabel = "item 1", tcFontConfig = Nothing }
        , Text TextConfig { tcLabel = "item 2", tcFontConfig = Nothing }
        ])

  , testCase "button inside ScrollView fires its callback" $ do
      ref <- newIORef (0 :: Int)
      rs <- newRenderState
      renderWidget rs $ ScrollView
        [ Button ButtonConfig
            { bcLabel = "press me", bcAction = modifyIORef' ref (+ 1), bcFontConfig = Nothing } ]
      dispatchEvent rs 0
      count <- readIORef ref
      count @?= 1

  , testCase "ScrollView with nested Column renders and dispatches correctly" $ do
      ref <- newIORef False
      rs <- newRenderState
      renderWidget rs $ ScrollView
        [ Column
          [ Text TextConfig { tcLabel = "header", tcFontConfig = Nothing }
          , Button ButtonConfig
              { bcLabel = "action", bcAction = modifyIORef' ref (const True), bcFontConfig = Nothing }
          ]
        ]
      dispatchEvent rs 0
      fired <- readIORef ref
      fired @?= True

  , testCase "re-render inside ScrollView resets callbacks" $ do
      refOld <- newIORef False
      refNew <- newIORef False
      rs <- newRenderState
      renderWidget rs $ ScrollView [Button ButtonConfig
        { bcLabel = "old", bcAction = modifyIORef' refOld (const True), bcFontConfig = Nothing }]
      renderWidget rs $ ScrollView [Button ButtonConfig
        { bcLabel = "new", bcAction = modifyIORef' refNew (const True), bcFontConfig = Nothing }]
      dispatchEvent rs 0
      old <- readIORef refOld
      new <- readIORef refNew
      old @?= False
      new @?= True
  ]

textInputTests :: TestTree
textInputTests = testGroup "TextInput"
  [ testCase "text callback fires with correct value" $ do
      ref <- newIORef ("" :: String)
      rs <- newRenderState
      let widget = TextInput TextInputConfig
            { tiInputType = InputText, tiHint = "hint", tiValue = ""
            , tiOnChange = \t -> modifyIORef' ref (const (show t))
            , tiFontConfig = Nothing }
      renderWidget rs widget
      -- Callback 0 is the text change handler
      dispatchTextEvent rs 0 "hello"
      val <- readIORef ref
      val @?= show ("hello" :: String)

  , testCase "text callback receives updated value" $ do
      ref <- newIORef ("" :: String)
      rs <- newRenderState
      let widget = TextInput TextInputConfig
            { tiInputType = InputText, tiHint = "enter weight", tiValue = "80"
            , tiOnChange = \t -> modifyIORef' ref (const (show t))
            , tiFontConfig = Nothing }
      renderWidget rs widget
      dispatchTextEvent rs 0 "95.5"
      val <- readIORef ref
      val @?= show ("95.5" :: String)

  , testCase "dispatchTextEvent with unknown ID does not crash" $ do
      rs <- newRenderState
      renderWidget rs (Text TextConfig { tcLabel = "no inputs", tcFontConfig = Nothing })
      -- Should not throw
      dispatchTextEvent rs 42 "ignored"
      dispatchTextEvent rs 999 "also ignored"

  , testCase "text and click callbacks share ID space without collision" $ do
      clickRef <- newIORef False
      textRef  <- newIORef ("" :: String)
      rs <- newRenderState
      let widget = Column
            [ Button ButtonConfig
                { bcLabel = "ok", bcAction = modifyIORef' clickRef (const True), bcFontConfig = Nothing }
            , TextInput TextInputConfig
                { tiInputType = InputText, tiHint = "hint", tiValue = ""
                , tiOnChange = \t -> modifyIORef' textRef (const (show t))
                , tiFontConfig = Nothing }
            ]
      renderWidget rs widget
      -- Button gets callback 0, TextInput gets callback 1
      dispatchEvent rs 0
      dispatchTextEvent rs 1 "typed"
      click <- readIORef clickRef
      text  <- readIORef textRef
      click @?= True
      text  @?= show ("typed" :: String)

  , testCase "re-render resets text callbacks" $ do
      refOld <- newIORef ("" :: String)
      refNew <- newIORef ("" :: String)
      rs <- newRenderState
      renderWidget rs $ TextInput TextInputConfig
        { tiInputType = InputText, tiHint = "old", tiValue = ""
        , tiOnChange = \t -> modifyIORef' refOld (const (show t))
        , tiFontConfig = Nothing }
      renderWidget rs $ TextInput TextInputConfig
        { tiInputType = InputText, tiHint = "new", tiValue = ""
        , tiOnChange = \t -> modifyIORef' refNew (const (show t))
        , tiFontConfig = Nothing }
      dispatchTextEvent rs 0 "val"
      old <- readIORef refOld
      new <- readIORef refNew
      old @?= ""
      new @?= show ("val" :: String)

  , testCase "InputNumber callback fires correctly" $ do
      ref <- newIORef ("" :: String)
      rs <- newRenderState
      let widget = TextInput TextInputConfig
            { tiInputType = InputNumber, tiHint = "weight", tiValue = ""
            , tiOnChange = \t -> modifyIORef' ref (const (show t))
            , tiFontConfig = Nothing }
      renderWidget rs widget
      dispatchTextEvent rs 0 "72.5"
      val <- readIORef ref
      val @?= show ("72.5" :: String)

  , testCase "InputText and InputNumber coexist with independent callbacks" $ do
      textRef   <- newIORef ("" :: String)
      numberRef <- newIORef ("" :: String)
      rs <- newRenderState
      let widget = Column
            [ TextInput TextInputConfig
                { tiInputType = InputText, tiHint = "name", tiValue = ""
                , tiOnChange = \t -> modifyIORef' textRef (const (show t))
                , tiFontConfig = Nothing }
            , TextInput TextInputConfig
                { tiInputType = InputNumber, tiHint = "weight", tiValue = ""
                , tiOnChange = \t -> modifyIORef' numberRef (const (show t))
                , tiFontConfig = Nothing }
            ]
      renderWidget rs widget
      -- TextInput gets callback 0, InputNumber gets callback 1
      dispatchTextEvent rs 0 "Alice"
      dispatchTextEvent rs 1 "60.0"
      tVal <- readIORef textRef
      nVal <- readIORef numberRef
      tVal @?= show ("Alice" :: String)
      nVal @?= show ("60.0" :: String)
  ]

-- | Tests for the Image widget binding.
imageTests :: TestTree
imageTests = testGroup "Image"
  [ testCase "Image with resource renders without error" $ do
      rs <- newRenderState
      renderWidget rs $ Image ImageConfig
        { icSource = ImageResource (ResourceName "ic_launcher"), icScaleType = ScaleFit }

  , testCase "Image with ByteString data renders without error" $ do
      rs <- newRenderState
      let bytes = BS.pack [0x89, 0x50, 0x4E, 0x47, 0x00, 0x00, 0x00, 0x00]
      renderWidget rs $ Image ImageConfig
        { icSource = ImageData bytes, icScaleType = ScaleFill }

  , testCase "Image with file path renders without error" $ do
      rs <- newRenderState
      renderWidget rs $ Image ImageConfig
        { icSource = ImageFile "/nonexistent/test.png", icScaleType = ScaleNone }

  , testCase "Image inside Column renders" $ do
      rs <- newRenderState
      renderWidget rs $ Column
        [ Text TextConfig { tcLabel = "header", tcFontConfig = Nothing }
        , Image ImageConfig
            { icSource = ImageResource (ResourceName "logo"), icScaleType = ScaleFit }
        ]

  , testCase "Styled Image renders without error" $ do
      rs <- newRenderState
      renderWidget rs $ Styled defaultStyle
        (Image ImageConfig
          { icSource = ImageResource (ResourceName "icon"), icScaleType = ScaleNone })

  , testCase "ScaleFit renders without error" $ do
      rs <- newRenderState
      renderWidget rs $ Image ImageConfig
        { icSource = ImageResource (ResourceName "fit_test"), icScaleType = ScaleFit }

  , testCase "ScaleFill renders without error" $ do
      rs <- newRenderState
      renderWidget rs $ Image ImageConfig
        { icSource = ImageResource (ResourceName "fill_test"), icScaleType = ScaleFill }

  , testCase "ScaleNone renders without error" $ do
      rs <- newRenderState
      renderWidget rs $ Image ImageConfig
        { icSource = ImageResource (ResourceName "none_test"), icScaleType = ScaleNone }
  ]

-- | Tests for the WebView widget.
webViewTests :: TestTree
webViewTests = testGroup "WebView"
  [ testCase "WebView renders without error" $ do
      rs <- newRenderState
      renderWidget rs $ WebView WebViewConfig
        { wvUrl = "https://example.com", wvOnPageLoad = Nothing }

  , testCase "WebView with callback registers handler and fires" $ do
      ref <- newIORef (0 :: Int)
      rs <- newRenderState
      renderWidget rs $ WebView WebViewConfig
        { wvUrl = "https://example.com"
        , wvOnPageLoad = Just (modifyIORef' ref (+ 1))
        }
      -- Callback 0 is registered for the page-load event
      dispatchEvent rs 0
      count <- readIORef ref
      count @?= 1

  , testCase "WebView without callback does not register handler" $ do
      rs <- newRenderState
      renderWidget rs $ WebView WebViewConfig
        { wvUrl = "https://example.com", wvOnPageLoad = Nothing }
      -- No callbacks registered, dispatching should log error but not crash
      dispatchEvent rs 0

  , testCase "WebView inside Column renders" $ do
      rs <- newRenderState
      renderWidget rs $ Column
        [ Text TextConfig { tcLabel = "header", tcFontConfig = Nothing }
        , WebView WebViewConfig
            { wvUrl = "https://example.com", wvOnPageLoad = Nothing }
        ]

  , testCase "Styled WebView renders without error" $ do
      rs <- newRenderState
      renderWidget rs $ Styled defaultStyle
        (WebView WebViewConfig
          { wvUrl = "https://example.com", wvOnPageLoad = Nothing })
  ]

-- | Tests for the Styled widget wrapper.
styledTests :: TestTree
styledTests = testGroup "Styled"
  [ testCase "Styled Text renders without error" $ do
      rs <- newRenderState
      renderWidget rs $ Styled (WidgetStyle (Just 8.0) Nothing Nothing Nothing)
        (Text TextConfig { tcLabel = "styled", tcFontConfig = Just (FontConfig 20.0) })

  , testCase "Styled Button fires callback" $ do
      ref <- newIORef (0 :: Int)
      rs <- newRenderState
      renderWidget rs $ Styled (WidgetStyle Nothing Nothing Nothing Nothing)
        (Button ButtonConfig
          { bcLabel = "tap", bcAction = modifyIORef' ref (+ 1)
          , bcFontConfig = Just (FontConfig 16.0) })
      dispatchEvent rs 0
      count <- readIORef ref
      count @?= 1

  , testCase "Styled Column renders children and dispatches" $ do
      ref <- newIORef False
      rs <- newRenderState
      renderWidget rs $ Styled defaultStyle
        (Column [ Text TextConfig { tcLabel = "info", tcFontConfig = Nothing }
                , Button ButtonConfig
                    { bcLabel = "go", bcAction = modifyIORef' ref (const True), bcFontConfig = Nothing }
                ])
      dispatchEvent rs 0
      fired <- readIORef ref
      fired @?= True

  , testCase "nested Styled applies both styles" $ do
      rs <- newRenderState
      renderWidget rs $
        Styled (WidgetStyle (Just 12.0) Nothing Nothing Nothing)
          (Styled (WidgetStyle Nothing Nothing Nothing Nothing)
            (Text TextConfig { tcLabel = "double styled", tcFontConfig = Just (FontConfig 18.0) }))

  , testCase "defaultStyle is a no-op" $ do
      rs <- newRenderState
      renderWidget rs $ Styled defaultStyle
        (Text TextConfig { tcLabel = "plain", tcFontConfig = Nothing })

  , testCase "re-render resets callbacks through Styled" $ do
      refOld <- newIORef False
      refNew <- newIORef False
      rs <- newRenderState
      renderWidget rs $ Styled defaultStyle
        (Button ButtonConfig
          { bcLabel = "old", bcAction = modifyIORef' refOld (const True), bcFontConfig = Nothing })
      renderWidget rs $ Styled defaultStyle
        (Button ButtonConfig
          { bcLabel = "new", bcAction = modifyIORef' refNew (const True), bcFontConfig = Nothing })
      dispatchEvent rs 0
      old <- readIORef refOld
      new <- readIORef refNew
      old @?= False
      new @?= True
  ]

-- | Tests for TextAlignment support in Styled widgets.
textAlignTests :: TestTree
textAlignTests = testGroup "TextAlignment"
  [ testCase "Styled with AlignCenter renders without error" $ do
      rs <- newRenderState
      renderWidget rs $ Styled (WidgetStyle Nothing (Just AlignCenter) Nothing Nothing)
        (Text TextConfig { tcLabel = "centered", tcFontConfig = Nothing })

  , testCase "Styled with AlignCenter on Button fires callback" $ do
      ref <- newIORef (0 :: Int)
      rs <- newRenderState
      renderWidget rs $ Styled (WidgetStyle Nothing (Just AlignCenter) Nothing Nothing)
        (Button ButtonConfig
          { bcLabel = "tap", bcAction = modifyIORef' ref (+ 1), bcFontConfig = Nothing })
      dispatchEvent rs 0
      count <- readIORef ref
      count @?= 1

  , testCase "defaultStyle has no text alignment" $
      wsTextAlign defaultStyle @?= Nothing

  , testCase "Styled with AlignEnd renders without error" $ do
      rs <- newRenderState
      renderWidget rs $ Styled (WidgetStyle Nothing (Just AlignEnd) Nothing Nothing)
        (Text TextConfig { tcLabel = "end aligned", tcFontConfig = Nothing })
  ]

-- | Tests for color support in Styled widgets.
colorTests :: TestTree
colorTests = testGroup "Colors"
  [ testCase "Styled with textColor renders and callback fires" $ do
      ref <- newIORef (0 :: Int)
      rs <- newRenderState
      renderWidget rs $ Styled (WidgetStyle Nothing Nothing (Just (Color 255 0 0 255)) Nothing)
        (Button ButtonConfig
          { bcLabel = "red", bcAction = modifyIORef' ref (+ 1), bcFontConfig = Nothing })
      dispatchEvent rs 0
      count <- readIORef ref
      count @?= 1

  , testCase "Styled with backgroundColor renders without error" $ do
      rs <- newRenderState
      renderWidget rs $ Styled (WidgetStyle Nothing Nothing Nothing (Just (Color 0 255 0 255)))
        (Text TextConfig { tcLabel = "green bg", tcFontConfig = Nothing })

  , testCase "both textColor and backgroundColor together" $ do
      ref <- newIORef (0 :: Int)
      rs <- newRenderState
      renderWidget rs $ Styled (WidgetStyle Nothing Nothing (Just (Color 255 0 0 255)) (Just (Color 0 255 0 255)))
        (Button ButtonConfig
          { bcLabel = "colored", bcAction = modifyIORef' ref (+ 1), bcFontConfig = Nothing })
      dispatchEvent rs 0
      count <- readIORef ref
      count @?= 1

  , testCase "defaultStyle has no colors" $ do
      wsTextColor defaultStyle @?= Nothing
      wsBackgroundColor defaultStyle @?= Nothing

  , testCase "nested Styled with different colors renders" $ do
      rs <- newRenderState
      renderWidget rs $
        Styled (WidgetStyle Nothing Nothing (Just (Color 255 0 0 255)) Nothing)
          (Styled (WidgetStyle Nothing Nothing Nothing (Just (Color 0 0 255 255)))
            (Text TextConfig { tcLabel = "nested colors", tcFontConfig = Nothing }))

  , testCase "colorFromText parses #RRGGBB" $
      colorFromText "#FF0000" @?= Just (Color 255 0 0 255)

  , testCase "colorFromText parses #RGB" $
      colorFromText "#F00" @?= Just (Color 255 0 0 255)

  , testCase "colorFromText parses #AARRGGBB" $
      colorFromText "#80FF0000" @?= Just (Color 255 0 0 128)

  , testCase "colorFromText rejects invalid input" $ do
      colorFromText "" @?= Nothing
      colorFromText "FF0000" @?= Nothing
      colorFromText "#GG0000" @?= Nothing

  , testCase "colorToHex roundtrips through colorFromText" $ do
      let color = Color 255 128 0 255
      colorFromText (colorToHex color) @?= Just color
  ]

-- | Tests for the AppContext-based registration.
-- Each test creates its own context, so no shared global state.
registrationTests :: TestTree
registrationTests = testGroup "Registration"
  [ testCase "startMobileApp returns working context" $ do
      ctxPtr <- startMobileApp mobileApp
      appCtx <- derefAppContext ctxPtr
      -- Verify the context has a working lifecycle callback
      mapM_ (onLifecycle (acMobileContext appCtx)) [Create, Destroy]
      freeAppContext ctxPtr

  , testCase "view function produces a widget through AppContext" $ do
      let customApp = MobileApp
            { maContext = MobileContext { onLifecycle = \_ -> pure (), onError = \_ -> pure () }
            , maView = \_userState -> pure (Text TextConfig { tcLabel = "custom", tcFontConfig = Nothing })
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
      let dummyUserState = UserState
            { userPermissionState    = dummyPermState
            , userSecureStorageState = dummySecureStorageState
            , userBleState           = dummyBleState
            , userDialogState        = dummyDialogState
            , userLocationState      = dummyLocationState
            , userAuthSessionState   = dummyAuthSessionState
            , userCameraState        = dummyCameraState
            }
      viewFn <- readIORef (acViewFunction appCtx)
      widget <- viewFn dummyUserState
      case widget of
        Text config -> tcLabel config @?= "custom"
        _           -> assertFailure "expected Text \"custom\""
      freeAppContext ctxPtr

  , testCase "two contexts are independent" $ do
      let appA = MobileApp
            { maContext = defaultMobileContext
            , maView = \_userState -> pure (Text TextConfig { tcLabel = "A", tcFontConfig = Nothing })
            }
          appB = MobileApp
            { maContext = defaultMobileContext
            , maView = \_userState -> pure (Text TextConfig { tcLabel = "B", tcFontConfig = Nothing })
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
      let dummyUserState = UserState
            { userPermissionState    = dummyPermState
            , userSecureStorageState = dummySecureStorageState
            , userBleState           = dummyBleState
            , userDialogState        = dummyDialogState
            , userLocationState      = dummyLocationState
            , userAuthSessionState   = dummyAuthSessionState
            , userCameraState        = dummyCameraState
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

localeTests :: TestTree
localeTests = testGroup "Locale"
  [ testCase "parseLocale parses language-only tag" $
      parseLocale "en" @?= Right (Locale En Nothing)
  , testCase "parseLocale parses language-region tag" $
      parseLocale "nl-NL" @?= Right (Locale Nl (Just "NL"))
  , testCase "parseLocale handles underscore separator" $
      parseLocale "en_US" @?= Right (Locale En (Just "US"))
  , testCase "parseLocale normalises case" $
      parseLocale "EN-us" @?= Right (Locale En (Just "US"))
  , testCase "parseLocale accepts 3-digit region code" $
      parseLocale "en-001" @?= Right (Locale En (Just "001"))
  , testCase "parseLocale rejects empty tag" $
      parseLocale "" @?= Left EmptyLocaleTag
  , testCase "parseLocale rejects unknown language code" $
      isLeft (parseLocale "xx") @?= True
  , testCase "parseLocale rejects invalid language" $
      isLeft (parseLocale "123") @?= True
  , testCase "parseLocale rejects single-char language" $
      isLeft (parseLocale "e") @?= True
  , testCase "localeToText roundtrips" $ do
      let locale = Locale Nl (Just "NL")
      parseLocale (localeToText locale) @?= Right locale
  , testCase "localeToText language-only" $
      localeToText (Locale En Nothing) @?= "en"
  , testCase "localeToText language-region" $
      localeToText (Locale Nl (Just "NL")) @?= "nl-NL"
  , testCase "getSystemLocale returns non-empty text" $ do
      locale <- getSystemLocale
      assertBool "locale should not be empty" (not (Text.null locale))
  ]

i18nTests :: TestTree
i18nTests = testGroup "I18n"
  [ testCase "translate finds exact locale match" $ do
      let translations = Map.fromList
            [ (Locale Nl (Just "NL"), Map.fromList [(Key "greeting", "Hallo")])
            , (Locale En Nothing,     Map.fromList [(Key "greeting", "Hello")])
            ]
      translate translations (Locale Nl (Just "NL")) (Key "greeting") @?= Right "Hallo"
  , testCase "translate falls back to language-only" $ do
      let translations = Map.fromList
            [ (Locale Nl Nothing, Map.fromList [(Key "greeting", "Hallo")])
            ]
      translate translations (Locale Nl (Just "BE")) (Key "greeting") @?= Right "Hallo"
  , testCase "translate reports KeyNotFound for missing key" $ do
      let translations = Map.fromList
            [ (Locale En Nothing, Map.fromList [(Key "greeting", "Hello")])
            ]
      translate translations (Locale En Nothing) (Key "farewell")
        @?= Left (KeyNotFound (Locale En Nothing) (Key "farewell"))
  , testCase "translate reports LocaleNotFound for missing locale" $ do
      let translations = Map.fromList
            [ (Locale En Nothing, Map.fromList [(Key "greeting", "Hello")])
            ]
      translate translations (Locale Ja Nothing) (Key "greeting")
        @?= Left (LocaleNotFound (Locale Ja Nothing))
  , testCase "translate prefers exact match over fallback" $ do
      let translations = Map.fromList
            [ (Locale Nl Nothing,       Map.fromList [(Key "greeting", "Hallo")])
            , (Locale Nl (Just "BE"),   Map.fromList [(Key "greeting", "Hoi")])
            ]
      translate translations (Locale Nl (Just "BE")) (Key "greeting") @?= Right "Hoi"
  ]

-- | Permission tests.  The @ffiPermState@ parameter is the 'PermissionState'
-- from a context created once in 'main' via 'startMobileApp'.  This
-- ensures the C desktop stub's @g_permission_ctx@ points to a valid context
-- for the FFI round-trip tests, without racing with other tests.
-- | Uses 'sequentialTestGroup' because these tests share a
-- 'PermissionState' with a mutable request ID counter.
permissionTests :: PermissionState -> TestTree
permissionTests ffiPermState = sequentialTestGroup "Permission" AllFinish
  [ testCase "requestPermission fires callback with PermissionGranted on desktop" $ do
      -- Uses the shared FFI context because the C desktop stub dispatches
      -- via haskellOnPermissionResult(g_permission_ctx, ...).
      ref <- newIORef (Nothing :: Maybe PermissionStatus)
      requestPermission ffiPermState PermissionCamera
        (\status -> modifyIORef' ref (const (Just status)))
      result <- readIORef ref
      result @?= Just PermissionGranted

  , testCase "checkPermission returns PermissionGranted on desktop" $ do
      status <- checkPermission PermissionLocation
      status @?= PermissionGranted

  , testCase "dispatchPermissionResult with PermissionDenied fires callback correctly" $ do
      ref <- newIORef (Nothing :: Maybe PermissionStatus)
      permState <- newPermissionState
      modifyIORef' (psCallbacks permState) (\_ ->
        IntMap.singleton 0 (\status -> modifyIORef' ref (const (Just status))))
      dispatchPermissionResult permState 0 1
      result <- readIORef ref
      result @?= Just PermissionDenied

  , testCase "callback is removed after dispatch (second dispatch is a no-op)" $ do
      ref <- newIORef (0 :: Int)
      permState <- newPermissionState
      modifyIORef' (psCallbacks permState) (\_ ->
        IntMap.singleton 0 (\_ -> modifyIORef' ref (+ 1)))
      dispatchPermissionResult permState 0 0
      count1 <- readIORef ref
      count1 @?= 1
      -- Second dispatch for same ID should be a no-op (callback removed)
      dispatchPermissionResult permState 0 0
      count2 <- readIORef ref
      count2 @?= 1

  , testCase "unknown request ID does not crash" $ do
      permState <- newPermissionState
      -- Should not throw (logs to stderr)
      dispatchPermissionResult permState 999 0

  , testCase "unknown status code does not fire callback" $ do
      ref <- newIORef (0 :: Int)
      permState <- newPermissionState
      modifyIORef' (psCallbacks permState) (\_ ->
        IntMap.singleton 0 (\_ -> modifyIORef' ref (+ 1)))
      dispatchPermissionResult permState 0 42
      count <- readIORef ref
      count @?= 0

  , testCase "multiple simultaneous pending requests dispatch independently" $ do
      -- Uses the shared FFI context for the desktop stub round-trip
      refA <- newIORef (Nothing :: Maybe PermissionStatus)
      refB <- newIORef (Nothing :: Maybe PermissionStatus)
      requestPermission ffiPermState PermissionCamera
        (\status -> modifyIORef' refA (const (Just status)))
      requestPermission ffiPermState PermissionContacts
        (\status -> modifyIORef' refB (const (Just status)))
      resultA <- readIORef refA
      resultB <- readIORef refB
      resultA @?= Just PermissionGranted
      resultB @?= Just PermissionGranted

  , testCase "permissionToInt covers all constructors" $ do
      permissionToInt PermissionLocation   @?= 0
      permissionToInt PermissionBluetooth  @?= 1
      permissionToInt PermissionCamera     @?= 2
      permissionToInt PermissionMicrophone @?= 3
      permissionToInt PermissionContacts   @?= 4
      permissionToInt PermissionStorage    @?= 5

  , testCase "permissionStatusFromInt roundtrips valid codes" $ do
      permissionStatusFromInt 0 @?= Just PermissionGranted
      permissionStatusFromInt 1 @?= Just PermissionDenied

  , testCase "permissionStatusFromInt returns Nothing for unknown codes" $ do
      permissionStatusFromInt 2 @?= Nothing
      permissionStatusFromInt (-1) @?= Nothing
      permissionStatusFromInt 100 @?= Nothing
  ]

-- | Secure storage tests.  The @ffiSecureStorageState@ parameter is the
-- 'SecureStorageState' from a context created once in 'main' via
-- 'haskellCreateContext', ensuring the C desktop stub dispatches through
-- a valid context pointer.
-- Uses 'sequentialTestGroup' because these tests share mutable state
-- (the C global key-value store and the Haskell callback registry).
secureStorageTests :: SecureStorageState -> TestTree
secureStorageTests ffiSecureStorageState = sequentialTestGroup "SecureStorage" AllFinish
  [ testCase "write then read returns written value" $ do
      statusRef <- newIORef (Nothing :: Maybe SecureStorageStatus)
      valueRef  <- newIORef (Nothing :: Maybe Text.Text)
      secureStorageWrite ffiSecureStorageState "test_key" "test_value"
        (\status -> modifyIORef' statusRef (const (Just status)))
      writeStatus <- readIORef statusRef
      writeStatus @?= Just StorageSuccess
      secureStorageRead ffiSecureStorageState "test_key"
        (\status maybeVal -> do
          modifyIORef' statusRef (const (Just status))
          modifyIORef' valueRef  (const maybeVal))
      readStatus <- readIORef statusRef
      readValue  <- readIORef valueRef
      readStatus @?= Just StorageSuccess
      readValue  @?= Just "test_value"

  , testCase "read nonexistent key returns StorageNotFound" $ do
      statusRef <- newIORef (Nothing :: Maybe SecureStorageStatus)
      valueRef  <- newIORef (Nothing :: Maybe Text.Text)
      secureStorageRead ffiSecureStorageState "nonexistent_key_12345"
        (\status maybeVal -> do
          modifyIORef' statusRef (const (Just status))
          modifyIORef' valueRef  (const maybeVal))
      readStatus <- readIORef statusRef
      readValue  <- readIORef valueRef
      readStatus @?= Just StorageNotFound
      readValue  @?= Nothing

  , testCase "delete then read returns StorageNotFound" $ do
      statusRef <- newIORef (Nothing :: Maybe SecureStorageStatus)
      valueRef  <- newIORef (Nothing :: Maybe Text.Text)
      -- Write a key first
      secureStorageWrite ffiSecureStorageState "delete_me" "some_value"
        (\_ -> pure ())
      -- Delete it
      secureStorageDelete ffiSecureStorageState "delete_me"
        (\status -> modifyIORef' statusRef (const (Just status)))
      deleteStatus <- readIORef statusRef
      deleteStatus @?= Just StorageSuccess
      -- Read it back — should be gone
      secureStorageRead ffiSecureStorageState "delete_me"
        (\status maybeVal -> do
          modifyIORef' statusRef (const (Just status))
          modifyIORef' valueRef  (const maybeVal))
      readStatus <- readIORef statusRef
      readValue  <- readIORef valueRef
      readStatus @?= Just StorageNotFound
      readValue  @?= Nothing

  , testCase "write overwrites existing value" $ do
      valueRef <- newIORef (Nothing :: Maybe Text.Text)
      secureStorageWrite ffiSecureStorageState "overwrite_key" "first"
        (\_ -> pure ())
      secureStorageWrite ffiSecureStorageState "overwrite_key" "second"
        (\_ -> pure ())
      secureStorageRead ffiSecureStorageState "overwrite_key"
        (\_ maybeVal -> modifyIORef' valueRef (const maybeVal))
      readValue <- readIORef valueRef
      readValue @?= Just "second"

  , testCase "write callback removed after dispatch" $ do
      ref <- newIORef (0 :: Int)
      storageState <- newSecureStorageState
      modifyIORef' (ssWriteCallbacks storageState) (\_ ->
        IntMap.singleton 0 (\_ -> modifyIORef' ref (+ 1)))
      dispatchSecureStorageResult storageState 0 0 Nothing
      count1 <- readIORef ref
      count1 @?= 1
      -- Second dispatch for same ID should be a no-op
      dispatchSecureStorageResult storageState 0 0 Nothing
      count2 <- readIORef ref
      count2 @?= 1

  , testCase "storageStatusFromInt roundtrips valid codes" $ do
      storageStatusFromInt 0 @?= Just StorageSuccess
      storageStatusFromInt 1 @?= Just StorageNotFound
      storageStatusFromInt 2 @?= Just StorageError

  , testCase "storageStatusFromInt rejects unknown codes" $ do
      storageStatusFromInt 3 @?= Nothing
      storageStatusFromInt (-1) @?= Nothing
      storageStatusFromInt 100 @?= Nothing

  , testCase "unknown request ID does not crash" $ do
      storageState <- newSecureStorageState
      -- Should not throw (logs to stderr)
      dispatchSecureStorageResult storageState 999 0 Nothing

  , testCase "unknown status code does not fire callback" $ do
      ref <- newIORef (0 :: Int)
      storageState <- newSecureStorageState
      modifyIORef' (ssWriteCallbacks storageState) (\_ ->
        IntMap.singleton 0 (\_ -> modifyIORef' ref (+ 1)))
      dispatchSecureStorageResult storageState 0 42 Nothing
      count <- readIORef ref
      count @?= 0
  ]

-- | BLE scanning tests.
-- The desktop stub reports adapter as ON and start/stop scan are no-ops,
-- so we can exercise the Haskell logic without native code.
bleTests :: TestTree
bleTests = testGroup "BLE"
  [ testCase "bleAdapterStatusFromInt roundtrips all constructors" $ do
      let allStatuses = [BleAdapterOff, BleAdapterOn, BleAdapterUnauthorized, BleAdapterUnsupported]
      mapM_ (\status ->
        bleAdapterStatusFromInt (bleAdapterStatusToInt status) @?= Just status
        ) allStatuses

  , testCase "bleAdapterStatusFromInt returns Nothing for unknown codes" $ do
      bleAdapterStatusFromInt 4 @?= Nothing
      bleAdapterStatusFromInt (-1) @?= Nothing
      bleAdapterStatusFromInt 100 @?= Nothing

  , testCase "bleAdapterStatusToInt produces expected codes" $ do
      bleAdapterStatusToInt BleAdapterOff          @?= 0
      bleAdapterStatusToInt BleAdapterOn           @?= 1
      bleAdapterStatusToInt BleAdapterUnauthorized @?= 2
      bleAdapterStatusToInt BleAdapterUnsupported  @?= 3

  , testCase "checkBleAdapter returns BleAdapterOn on desktop" $ do
      status <- checkBleAdapter
      status @?= BleAdapterOn

  , testCase "startBleScan registers callback" $ do
      bleState <- newBleState
      startBleScan bleState (\_ -> pure ())
      maybeCb <- readIORef (blesScanCallback bleState)
      case maybeCb of
        Nothing -> assertFailure "callback should be Just after startBleScan"
        Just _  -> pure ()

  , testCase "stopBleScan clears callback" $ do
      bleState <- newBleState
      startBleScan bleState (\_ -> pure ())
      stopBleScan bleState
      maybeCb <- readIORef (blesScanCallback bleState)
      case maybeCb of
        Nothing -> pure ()
        Just _  -> assertFailure "callback should be Nothing after stopBleScan"

  , testCase "dispatchBleScanResult fires registered callback" $ do
      bleState <- newBleState
      ref <- newIORef (Nothing :: Maybe BleScanResult)
      startBleScan bleState (\result -> writeIORef ref (Just result))
      cName <- newCString "TestDevice"
      cAddr <- newCString "AA:BB:CC:DD:EE:FF"
      dispatchBleScanResult bleState cName cAddr (-42)
      free cName
      free cAddr
      result <- readIORef ref
      case result of
        Nothing -> assertFailure "callback should have been fired"
        Just scanResult -> do
          bsrDeviceName scanResult @?= "TestDevice"
          bsrDeviceAddress scanResult @?= "AA:BB:CC:DD:EE:FF"
          bsrRssi scanResult @?= (-42)

  , testCase "dispatchBleScanResult with no active scan is no-op" $ do
      bleState <- newBleState
      cName <- newCString "Ignored"
      cAddr <- newCString "00:00:00:00:00:00"
      -- Should not throw or crash
      dispatchBleScanResult bleState cName cAddr 0
      free cName
      free cAddr

  , testCase "multiple scan results accumulate" $ do
      bleState <- newBleState
      ref <- newIORef ([] :: [BleScanResult])
      startBleScan bleState (\result -> modifyIORef' ref (++ [result]))
      cName1 <- newCString "Device1"
      cAddr1 <- newCString "11:22:33:44:55:66"
      dispatchBleScanResult bleState cName1 cAddr1 (-50)
      free cName1
      free cAddr1
      cName2 <- newCString "Device2"
      cAddr2 <- newCString "AA:BB:CC:DD:EE:FF"
      dispatchBleScanResult bleState cName2 cAddr2 (-70)
      free cName2
      free cAddr2
      results <- readIORef ref
      length results @?= 2
      case results of
        [first, second] -> do
          bsrDeviceName first @?= "Device1"
          bsrDeviceName second @?= "Device2"
        _ -> assertFailure "expected exactly 2 results"

  , testCase "startBleScan replaces existing callback" $ do
      bleState <- newBleState
      refOld <- newIORef (0 :: Int)
      refNew <- newIORef (0 :: Int)
      startBleScan bleState (\_ -> modifyIORef' refOld (+ 1))
      -- Replace with new callback
      startBleScan bleState (\_ -> modifyIORef' refNew (+ 1))
      cName <- newCString "Test"
      cAddr <- newCString "00:11:22:33:44:55"
      dispatchBleScanResult bleState cName cAddr (-60)
      free cName
      free cAddr
      oldCount <- readIORef refOld
      newCount <- readIORef refNew
      oldCount @?= 0
      newCount @?= 1

  , testCase "null device name handled as empty Text" $ do
      bleState <- newBleState
      ref <- newIORef (Nothing :: Maybe BleScanResult)
      startBleScan bleState (\result -> writeIORef ref (Just result))
      cAddr <- newCString "FF:EE:DD:CC:BB:AA"
      dispatchBleScanResult bleState nullPtr cAddr (-80)
      free cAddr
      result <- readIORef ref
      case result of
        Nothing -> assertFailure "callback should have been fired"
        Just scanResult -> do
          bsrDeviceName scanResult @?= ""
          bsrDeviceAddress scanResult @?= "FF:EE:DD:CC:BB:AA"
  ]

-- | Dialog tests.  The @ffiDialogState@ parameter is the 'DialogState'
-- from a context created once in 'main' via 'startMobileApp'.  This
-- ensures the C desktop stub's context pointer is valid for FFI round-trip
-- tests.
-- Uses 'sequentialTestGroup' because these tests share mutable state
-- (the Haskell callback registry and the C global context pointer).
dialogTests :: DialogState -> TestTree
dialogTests ffiDialogState = sequentialTestGroup "Dialog" AllFinish
  [ testCase "showDialog registers callback and desktop stub fires button1" $ do
      ref <- newIORef (Nothing :: Maybe DialogAction)
      showDialog ffiDialogState
        DialogConfig
          { dcTitle   = "Test Alert"
          , dcMessage = "A test message"
          , dcButton1 = "OK"
          , dcButton2 = Nothing
          , dcButton3 = Nothing
          }
        (\action -> writeIORef ref (Just action))
      result <- readIORef ref
      result @?= Just DialogButton1

  , testCase "dispatchDialogResult fires registered callback" $ do
      ref <- newIORef (Nothing :: Maybe DialogAction)
      dialogState <- newDialogState
      modifyIORef' (dsCallbacks dialogState) (\_ ->
        IntMap.singleton 0 (\action -> writeIORef ref (Just action)))
      dispatchDialogResult dialogState 0 1  -- button2
      result <- readIORef ref
      result @?= Just DialogButton2

  , testCase "dispatchDialogResult with DialogDismissed" $ do
      ref <- newIORef (Nothing :: Maybe DialogAction)
      dialogState <- newDialogState
      modifyIORef' (dsCallbacks dialogState) (\_ ->
        IntMap.singleton 0 (\action -> writeIORef ref (Just action)))
      dispatchDialogResult dialogState 0 3  -- dismissed
      result <- readIORef ref
      result @?= Just DialogDismissed

  , testCase "dispatchDialogResult removes callback after firing" $ do
      ref <- newIORef (0 :: Int)
      dialogState <- newDialogState
      modifyIORef' (dsCallbacks dialogState) (\_ ->
        IntMap.singleton 0 (\_ -> modifyIORef' ref (+ 1)))
      dispatchDialogResult dialogState 0 0
      count1 <- readIORef ref
      count1 @?= 1
      -- Second dispatch for same ID should be a no-op (callback removed)
      dispatchDialogResult dialogState 0 0
      count2 <- readIORef ref
      count2 @?= 1

  , testCase "unknown requestId is silently logged" $ do
      dialogState <- newDialogState
      -- Should not throw (logs to stderr)
      dispatchDialogResult dialogState 999 0

  , testCase "unknown action code is silently logged" $ do
      ref <- newIORef (0 :: Int)
      dialogState <- newDialogState
      modifyIORef' (dsCallbacks dialogState) (\_ ->
        IntMap.singleton 0 (\_ -> modifyIORef' ref (+ 1)))
      dispatchDialogResult dialogState 0 42
      count <- readIORef ref
      count @?= 0

  , testCase "dialogActionFromInt round-trips" $ do
      dialogActionFromInt 0 @?= Just DialogButton1
      dialogActionFromInt 1 @?= Just DialogButton2
      dialogActionFromInt 2 @?= Just DialogButton3
      dialogActionFromInt 3 @?= Just DialogDismissed
      dialogActionFromInt 4 @?= Nothing
      dialogActionFromInt (-1) @?= Nothing
      dialogActionFromInt 100 @?= Nothing
  ]

authSessionTests :: AuthSessionState -> TestTree
authSessionTests ffiAuthSessionState = sequentialTestGroup "AuthSession" AllFinish
  [ testCase "desktop stub returns success with fake redirect URL" $ do
      ref <- newIORef (Nothing :: Maybe AuthSessionResult)
      startAuthSession ffiAuthSessionState
        "https://example.com/auth?client_id=demo"
        "haskellmobile"
        (\result -> writeIORef ref (Just result))
      result <- readIORef ref
      case result of
        Just (AuthSessionSuccess redirectUrl) -> do
          assertBool "redirect URL contains scheme" ("haskellmobile://" `Text.isPrefixOf` redirectUrl)
          assertBool "redirect URL contains code param" ("code=DESKTOP_STUB_CODE" `Text.isInfixOf` redirectUrl)
        _ -> assertFailure $ "expected AuthSessionSuccess, got: " ++ show result

  , testCase "dispatchAuthSessionResult fires Success callback with redirect URL" $ do
      ref <- newIORef (Nothing :: Maybe AuthSessionResult)
      authState <- newAuthSessionState
      modifyIORef' (asCallbacks authState) (\_ ->
        IntMap.singleton 0 (\result -> writeIORef ref (Just result)))
      dispatchAuthSessionResult authState 0 0 (Just "myapp://cb?code=abc") Nothing
      result <- readIORef ref
      result @?= Just (AuthSessionSuccess "myapp://cb?code=abc")

  , testCase "dispatchAuthSessionResult fires Cancelled callback" $ do
      ref <- newIORef (Nothing :: Maybe AuthSessionResult)
      authState <- newAuthSessionState
      modifyIORef' (asCallbacks authState) (\_ ->
        IntMap.singleton 0 (\result -> writeIORef ref (Just result)))
      dispatchAuthSessionResult authState 0 1 Nothing Nothing
      result <- readIORef ref
      result @?= Just AuthSessionCancelled

  , testCase "dispatchAuthSessionResult fires Error callback with message" $ do
      ref <- newIORef (Nothing :: Maybe AuthSessionResult)
      authState <- newAuthSessionState
      modifyIORef' (asCallbacks authState) (\_ ->
        IntMap.singleton 0 (\result -> writeIORef ref (Just result)))
      dispatchAuthSessionResult authState 0 2 Nothing (Just "network error")
      result <- readIORef ref
      result @?= Just (AuthSessionError "network error")

  , testCase "callback removed after dispatch (idempotency)" $ do
      ref <- newIORef (0 :: Int)
      authState <- newAuthSessionState
      modifyIORef' (asCallbacks authState) (\_ ->
        IntMap.singleton 0 (\_ -> modifyIORef' ref (+ 1)))
      dispatchAuthSessionResult authState 0 0 (Just "myapp://cb") Nothing
      count1 <- readIORef ref
      count1 @?= 1
      -- Second dispatch for same ID should be a no-op (callback removed)
      dispatchAuthSessionResult authState 0 0 (Just "myapp://cb") Nothing
      count2 <- readIORef ref
      count2 @?= 1

  , testCase "authSessionResultFromInt roundtrips valid codes" $ do
      authSessionResultFromInt 0 (Just "url") Nothing @?= Just (AuthSessionSuccess "url")
      authSessionResultFromInt 1 Nothing Nothing @?= Just AuthSessionCancelled
      authSessionResultFromInt 2 Nothing (Just "err") @?= Just (AuthSessionError "err")

  , testCase "authSessionResultFromInt rejects unknown codes" $ do
      authSessionResultFromInt 3 Nothing Nothing @?= Nothing
      authSessionResultFromInt (-1) Nothing Nothing @?= Nothing
      authSessionResultFromInt 100 Nothing Nothing @?= Nothing

  , testCase "unknown requestId does not crash" $ do
      authState <- newAuthSessionState
      -- Should not throw (logs to stderr)
      dispatchAuthSessionResult authState 999 0 (Just "url") Nothing

  , testCase "unknown status code does not fire callback" $ do
      ref <- newIORef (0 :: Int)
      authState <- newAuthSessionState
      modifyIORef' (asCallbacks authState) (\_ ->
        IntMap.singleton 0 (\_ -> modifyIORef' ref (+ 1)))
      dispatchAuthSessionResult authState 0 42 Nothing Nothing
      count <- readIORef ref
      count @?= 0
  ]

locationTests :: TestTree
locationTests = testGroup "Location"
  [ testCase "desktop stub dispatches fixed location on startLocationUpdates" $ do
      let app = MobileApp
            { maContext = defaultMobileContext
            , maView = \_userState -> pure (Text TextConfig { tcLabel = "dummy", tcFontConfig = Nothing })
            }
      ctxPtr <- newAppContext app
      appCtx <- derefAppContext ctxPtr
      let locationState = acLocationState appCtx
      ref <- newIORef (Nothing :: Maybe LocationData)
      startLocationUpdates locationState (\loc -> writeIORef ref (Just loc))
      result <- readIORef ref
      case result of
        Nothing -> assertFailure "callback should have been fired by desktop stub"
        Just loc -> do
          -- Desktop stub dispatches lat=52.37, lon=4.90, alt=0.0, acc=10.0
          ldLatitude loc @?= 52.37
          ldLongitude loc @?= 4.90
          ldAltitude loc @?= 0.0
          ldAccuracy loc @?= 10.0
      freeAppContext ctxPtr

  , testCase "dispatchLocationUpdate fires callback with correct LocationData" $ do
      locationState <- newLocationState
      ref <- newIORef (Nothing :: Maybe LocationData)
      writeIORef (lsUpdateCallback locationState) (Just (\loc -> writeIORef ref (Just loc)))
      dispatchLocationUpdate locationState 48.86 2.35 35.0 5.0
      result <- readIORef ref
      case result of
        Nothing -> assertFailure "callback should have been fired"
        Just loc -> do
          ldLatitude loc @?= 48.86
          ldLongitude loc @?= 2.35
          ldAltitude loc @?= 35.0
          ldAccuracy loc @?= 5.0

  , testCase "dispatchLocationUpdate with no active listener is no-op" $ do
      locationState <- newLocationState
      -- Should not throw or crash
      dispatchLocationUpdate locationState 0.0 0.0 0.0 0.0

  , testCase "stopLocationUpdates clears callback" $ do
      let app = MobileApp
            { maContext = defaultMobileContext
            , maView = \_userState -> pure (Text TextConfig { tcLabel = "dummy", tcFontConfig = Nothing })
            }
      ctxPtr <- newAppContext app
      appCtx <- derefAppContext ctxPtr
      let locationState = acLocationState appCtx
      startLocationUpdates locationState (\_ -> pure ())
      stopLocationUpdates locationState
      maybeCb <- readIORef (lsUpdateCallback locationState)
      case maybeCb of
        Nothing -> pure ()
        Just _  -> assertFailure "callback should be Nothing after stopLocationUpdates"
      freeAppContext ctxPtr

  , testCase "startLocationUpdates replaces existing callback" $ do
      let app = MobileApp
            { maContext = defaultMobileContext
            , maView = \_userState -> pure (Text TextConfig { tcLabel = "dummy", tcFontConfig = Nothing })
            }
      ctxPtr <- newAppContext app
      appCtx <- derefAppContext ctxPtr
      let locationState = acLocationState appCtx
      refOld <- newIORef (0 :: Int)
      refNew <- newIORef (0 :: Int)
      writeIORef (lsUpdateCallback locationState) (Just (\_ -> modifyIORef' refOld (+ 1)))
      -- Replace with new callback (startLocationUpdates calls stop first on the C side,
      -- then installs new callback, then calls start which dispatches stub location)
      startLocationUpdates locationState (\_ -> modifyIORef' refNew (+ 1))
      oldCount <- readIORef refOld
      newCount <- readIORef refNew
      oldCount @?= 0
      -- Desktop stub dispatches one location on start, so newCount should be 1
      newCount @?= 1
      freeAppContext ctxPtr
  ]

-- | Tests for the AppContext FFI path.
cameraTests :: TestTree
cameraTests = testGroup "Camera"
  [ testCase "desktop stub dispatches success on capturePhoto" $ do
      let app = MobileApp
            { maContext = defaultMobileContext
            , maView = \_userState -> pure (Text TextConfig { tcLabel = "dummy", tcFontConfig = Nothing })
            }
      ctxPtr <- newAppContext app
      appCtx <- derefAppContext ctxPtr
      let cameraState = acCameraState appCtx
      ref <- newIORef (Nothing :: Maybe CameraResult)
      capturePhoto cameraState (\result -> writeIORef ref (Just result))
      maybeResult <- readIORef ref
      case maybeResult of
        Nothing -> assertFailure "callback should have been fired by desktop stub"
        Just result -> do
          crStatus result @?= CameraSuccess
          -- Desktop stub returns a dummy path
          case crFilePath result of
            Nothing -> assertFailure "file path should be present on success"
            Just _  -> pure ()
      freeAppContext ctxPtr

  , testCase "desktop stub dispatches success on startVideoCapture" $ do
      let app = MobileApp
            { maContext = defaultMobileContext
            , maView = \_userState -> pure (Text TextConfig { tcLabel = "dummy", tcFontConfig = Nothing })
            }
      ctxPtr <- newAppContext app
      appCtx <- derefAppContext ctxPtr
      let cameraState = acCameraState appCtx
      ref <- newIORef (Nothing :: Maybe CameraResult)
      startVideoCapture cameraState (\result -> writeIORef ref (Just result))
      maybeResult <- readIORef ref
      case maybeResult of
        Nothing -> assertFailure "callback should have been fired by desktop stub"
        Just result -> do
          crStatus result @?= CameraSuccess
          case crFilePath result of
            Nothing -> assertFailure "file path should be present on success"
            Just _  -> pure ()
      freeAppContext ctxPtr

  , testCase "dispatchCameraResult fires callback with correct CameraResult" $ do
      cameraState <- newCameraState
      ref <- newIORef (Nothing :: Maybe CameraResult)
      modifyIORef' (csCallbacks cameraState)
        (IntMap.insert 0 (\result -> writeIORef ref (Just result)))
      dispatchCameraResult cameraState 0 0 (Just "/tmp/photo.jpg")
      maybeResult <- readIORef ref
      case maybeResult of
        Nothing -> assertFailure "callback should have been fired"
        Just result -> do
          crStatus result @?= CameraSuccess
          crFilePath result @?= Just "/tmp/photo.jpg"

  , testCase "dispatchCameraResult with no callback is no-op" $ do
      cameraState <- newCameraState
      -- Should not throw or crash
      dispatchCameraResult cameraState 99 0 Nothing

  , testCase "capturePhoto assigns incremental request IDs" $ do
      let app = MobileApp
            { maContext = defaultMobileContext
            , maView = \_userState -> pure (Text TextConfig { tcLabel = "dummy", tcFontConfig = Nothing })
            }
      ctxPtr <- newAppContext app
      appCtx <- derefAppContext ctxPtr
      let cameraState = acCameraState appCtx
      idsBefore <- readIORef (csNextId cameraState)
      idsBefore @?= 0
      -- Register two captures — each should increment the ID
      capturePhoto cameraState (\_ -> pure ())
      idsAfter1 <- readIORef (csNextId cameraState)
      idsAfter1 @?= 1
      capturePhoto cameraState (\_ -> pure ())
      idsAfter2 <- readIORef (csNextId cameraState)
      idsAfter2 @?= 2
      freeAppContext ctxPtr

  , testCase "cameraStatusFromInt round-trips known codes" $ do
      cameraStatusFromInt 0 @?= Just CameraSuccess
      cameraStatusFromInt 1 @?= Just CameraCancelled
      cameraStatusFromInt 2 @?= Just CameraPermissionDenied
      cameraStatusFromInt 3 @?= Just CameraUnavailable
      cameraStatusFromInt 4 @?= Just CameraError
      cameraStatusFromInt 5 @?= Nothing
      cameraStatusFromInt (-1) @?= Nothing

  , testCase "cameraSourceToInt maps sources correctly" $ do
      cameraSourceToInt CameraBack @?= 0
      cameraSourceToInt CameraFront @?= 1

  , testCase "stopCameraSession is safe when no session active" $ do
      cameraState <- newCameraState
      -- Should not throw or crash
      stopCameraSession cameraState
  ]

appContextTests :: TestTree
appContextTests = testGroup "AppContext"
  [ testCase "newAppContext produces working lifecycle context" $ do
      ref <- newIORef ([] :: [LifecycleEvent])
      let app = MobileApp
            { maContext = MobileContext { onLifecycle = \event -> modifyIORef' ref (++ [event]), onError = \_ -> pure () }
            , maView = \_userState -> pure (Text TextConfig { tcLabel = "dummy", tcFontConfig = Nothing })
            }
      ctxPtr <- newAppContext app
      haskellOnLifecycle ctxPtr 0  -- Create
      haskellOnLifecycle ctxPtr 2  -- Resume
      haskellOnLifecycle ctxPtr 5  -- Destroy
      freeAppContext ctxPtr
      received <- readIORef ref
      received @?= [Create, Resume, Destroy]
  ]

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
    Row _                    -> pure False
    ScrollView _             -> pure False
    CameraView _             -> pure False
    Styled _ _               -> pure False

-- | Tests for the default exception handler that wraps FFI entry points.
-- Each test creates its own context, so no shared global mutation.
exceptionHandlerTests :: TestTree
exceptionHandlerTests = testGroup "ExceptionHandler"
  [ testCase "exception in view is caught and view replaced with error widget" $ do
      let crashingApp = MobileApp
            { maContext = defaultMobileContext
            , maView    = \_userState -> throwIO (userError "test-boom")
            }
      ctxPtr <- newAppContext crashingApp
      haskellRenderUI ctxPtr
      isError <- viewIsErrorWidget ctxPtr
      assertBool "view should be replaced with error widget" isError
      freeAppContext ctxPtr

  , testCase "exception in button callback is caught" $ do
      let crashingApp = MobileApp
            { maContext = defaultMobileContext
            , maView    = \_userState -> pure $ Button ButtonConfig
                { bcLabel  = "crash"
                , bcAction = throwIO (userError "button-boom")
                , bcFontConfig = Nothing
                }
            }
      ctxPtr <- newAppContext crashingApp
      -- First render to register the button callback
      haskellRenderUI ctxPtr
      -- Dispatch the button, which throws — handler overwrites view
      haskellOnUIEvent ctxPtr 0
      isError <- viewIsErrorWidget ctxPtr
      assertBool "view should be error widget after button callback exception" isError
      freeAppContext ctxPtr

  , testCase "dismiss restores original view after transient error" $ do
      -- Transient error: throws once, then succeeds
      shouldThrow <- newIORef True
      let transientView _userState = do
            throwing <- readIORef shouldThrow
            if throwing
              then do
                writeIORef shouldThrow False
                throwIO (userError "transient-error")
              else pure $ Text TextConfig { tcLabel = "recovered", tcFontConfig = Nothing }
          transientApp = MobileApp
            { maContext = defaultMobileContext
            , maView    = transientView
            }
      ctxPtr <- newAppContext transientApp
      -- First render throws, error widget shown, flag cleared
      haskellRenderUI ctxPtr
      isError <- viewIsErrorWidget ctxPtr
      assertBool "should show error widget" isError
      -- Dispatch callback 0 (the dismiss button in the error widget).
      -- This restores the original transientView, which now succeeds.
      haskellOnUIEvent ctxPtr 0
      isStillError <- viewIsErrorWidget ctxPtr
      assertBool "should no longer show error widget after dismiss" (not isStillError)
      freeAppContext ctxPtr

  , testCase "onError callback fires on exception" $ do
      ref <- newIORef (Nothing :: Maybe String)
      let ctx = MobileContext
            { onLifecycle = \_ -> pure ()
            , onError     = \exc -> writeIORef ref (Just (show exc))
            }
          crashingApp = MobileApp
            { maContext = ctx
            , maView    = \_userState -> throwIO (userError "onError-test")
            }
      ctxPtr <- newAppContext crashingApp
      haskellRenderUI ctxPtr
      firedValue <- readIORef ref
      case firedValue of
        Nothing  -> assertFailure "onError callback should have been fired"
        Just msg -> assertBool "onError should receive the exception" ("onError-test" `isInfixOf` msg)
      freeAppContext ctxPtr

  , testCase "exception in onError does not crash" $ do
      let ctx = MobileContext
            { onLifecycle = \_ -> pure ()
            , onError     = \_ -> throwIO (userError "secondary-boom")
            }
          crashingApp = MobileApp
            { maContext = ctx
            , maView    = \_userState -> throwIO (userError "primary-boom")
            }
      ctxPtr <- newAppContext crashingApp
      -- Should not crash despite both view and onError throwing
      result <- try @IOException (haskellRenderUI ctxPtr)
      case result of
        Left exc -> assertFailure ("haskellRenderUI should not throw, but got: " ++ show exc)
        Right () -> pure ()
      freeAppContext ctxPtr

  , testCase "exception in lifecycle handler is caught" $ do
      let crashingApp = MobileApp
            { maContext = MobileContext
                { onLifecycle = \_ -> throwIO (userError "lifecycle-boom")
                , onError     = \_ -> pure ()
                }
            , maView = \_userState -> pure (Text TextConfig { tcLabel = "dummy", tcFontConfig = Nothing })
            }
      ctxPtr <- newAppContext crashingApp
      -- Should not crash
      result <- try @IOException (haskellOnLifecycle ctxPtr 0)
      case result of
        Left exc -> assertFailure ("haskellOnLifecycle should not throw, but got: " ++ show exc)
        Right () -> pure ()
      freeAppContext ctxPtr
  ]
