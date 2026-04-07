module Main where

import Test.Tasty
import Test.Tasty.QuickCheck as QC
import Test.Tasty.HUnit

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
import Foreign.StablePtr (castStablePtrToPtr)
import HaskellMobile
  ( MobileApp(..)
  , AppState(..)
  , runMobileApp
  , getMobileApp
  , haskellGreet
  , haskellRenderUI
  , haskellOnUIEvent
  , globalAppState
  , dismissError
  )
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
  , newMobileContext
  , freeMobileContext
  , haskellOnLifecycle
  )
import HaskellMobile.Widget (ButtonConfig(..), FontConfig(..), InputType(..), TextAlignment(..), TextConfig(..), TextInputConfig(..), Widget(..), WidgetStyle(..), defaultStyle)
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
import HaskellMobile.Render (newRenderState, renderWidget, dispatchEvent, dispatchTextEvent)

main :: IO ()
main = do
  -- Register the default app so FFI functions that read the IORef work
  runMobileApp mobileApp
  defaultMain tests

tests :: TestTree
tests = testGroup "Tests" [qcProps, unitTests, lifecycleTests, uiTests, scrollViewTests, textInputTests, styledTests, textAlignTests, registrationTests, localeTests, i18nTests, permissionTests, exceptionHandlerTests]

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

-- | Helper: create a context with the given callback, run an action with
-- the opaque 'Ptr ()', then free the context.
withContext :: (LifecycleEvent -> IO ()) -> (Ptr () -> IO a) -> IO a
withContext callback action = do
  sptr <- newMobileContext MobileContext { onLifecycle = callback, onError = \_ -> pure () }
  let ptr = castStablePtrToPtr sptr
  result <- action ptr
  freeMobileContext sptr
  pure result

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
      widget <- maView mobileApp
      -- mobileApp is the counter demo; verify it's a column
      case widget of
        Column _        -> pure ()
        Text _          -> assertFailure "expected Column, got Text"
        Button _        -> assertFailure "expected Column, got Button"
        TextInput _     -> assertFailure "expected Column, got TextInput"
        Row _           -> assertFailure "expected Column, got Row"
        ScrollView _    -> assertFailure "expected Column, got ScrollView"
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

-- | Tests for the Styled widget wrapper.
styledTests :: TestTree
styledTests = testGroup "Styled"
  [ testCase "Styled Text renders without error" $ do
      rs <- newRenderState
      renderWidget rs $ Styled (WidgetStyle (Just 8.0) Nothing)
        (Text TextConfig { tcLabel = "styled", tcFontConfig = Just (FontConfig 20.0) })

  , testCase "Styled Button fires callback" $ do
      ref <- newIORef (0 :: Int)
      rs <- newRenderState
      renderWidget rs $ Styled (WidgetStyle Nothing Nothing)
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
        Styled (WidgetStyle (Just 12.0) Nothing)
          (Styled (WidgetStyle Nothing Nothing)
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
      renderWidget rs $ Styled (WidgetStyle Nothing (Just AlignCenter))
        (Text TextConfig { tcLabel = "centered", tcFontConfig = Nothing })

  , testCase "Styled with AlignCenter on Button fires callback" $ do
      ref <- newIORef (0 :: Int)
      rs <- newRenderState
      renderWidget rs $ Styled (WidgetStyle Nothing (Just AlignCenter))
        (Button ButtonConfig
          { bcLabel = "tap", bcAction = modifyIORef' ref (+ 1), bcFontConfig = Nothing })
      dispatchEvent rs 0
      count <- readIORef ref
      count @?= 1

  , testCase "defaultStyle has no text alignment" $
      wsTextAlign defaultStyle @?= Nothing

  , testCase "Styled with AlignEnd renders without error" $ do
      rs <- newRenderState
      renderWidget rs $ Styled (WidgetStyle Nothing (Just AlignEnd))
        (Text TextConfig { tcLabel = "end aligned", tcFontConfig = Nothing })
  ]

-- | Tests for the IORef registration pattern.
-- Uses 'sequentialTestGroup' because these tests modify the global mobileApp registration.
registrationTests :: TestTree
registrationTests = sequentialTestGroup "Registration" AllFinish
  [ testCase "getMobileApp returns the registered app" $ do
      app <- getMobileApp
      -- The app was registered in main before defaultMain.
      -- Verify it has the same context as mobileApp.
      mapM_ (onLifecycle (maContext app)) [Create, Destroy]

  , testCase "runMobileApp overwrites previous registration" $ do
      let customCtx = MobileContext { onLifecycle = \_ -> pure (), onError = \_ -> pure () }
          customApp = MobileApp { maContext = customCtx, maView = pure (Text TextConfig { tcLabel = "custom", tcFontConfig = Nothing }) }
      runMobileApp customApp
      app <- getMobileApp
      widget <- maView app
      case widget of
        Text config -> tcLabel config @?= "custom"
        _           -> assertFailure "expected Text \"custom\""
      -- Restore the original
      runMobileApp mobileApp
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

permissionTests :: TestTree
permissionTests = testGroup "Permission"
  [ testCase "requestPermission fires callback with PermissionGranted on desktop" $ do
      -- Uses (appPermissionState globalAppState) because the C desktop stub dispatches
      -- via haskellOnPermissionResult which targets the global state.
      ref <- newIORef (Nothing :: Maybe PermissionStatus)
      requestPermission (appPermissionState globalAppState) PermissionCamera
        (\status -> modifyIORef' ref (const (Just status)))
      result <- readIORef ref
      result @?= Just PermissionGranted

  , testCase "checkPermission returns PermissionGranted on desktop" $ do
      status <- checkPermission PermissionLocation
      status @?= PermissionGranted

  , testCase "dispatchPermissionResult with PermissionDenied fires callback correctly" $ do
      ref <- newIORef (Nothing :: Maybe PermissionStatus)
      ps <- newPermissionState
      modifyIORef' (psCallbacks ps) (\_ ->
        IntMap.singleton 0 (\status -> modifyIORef' ref (const (Just status))))
      dispatchPermissionResult ps 0 1
      result <- readIORef ref
      result @?= Just PermissionDenied

  , testCase "callback is removed after dispatch (second dispatch is a no-op)" $ do
      ref <- newIORef (0 :: Int)
      ps <- newPermissionState
      modifyIORef' (psCallbacks ps) (\_ ->
        IntMap.singleton 0 (\_ -> modifyIORef' ref (+ 1)))
      dispatchPermissionResult ps 0 0
      count1 <- readIORef ref
      count1 @?= 1
      -- Second dispatch for same ID should be a no-op (callback removed)
      dispatchPermissionResult ps 0 0
      count2 <- readIORef ref
      count2 @?= 1

  , testCase "unknown request ID does not crash" $ do
      ps <- newPermissionState
      -- Should not throw (logs to stderr)
      dispatchPermissionResult ps 999 0

  , testCase "unknown status code does not fire callback" $ do
      ref <- newIORef (0 :: Int)
      ps <- newPermissionState
      modifyIORef' (psCallbacks ps) (\_ ->
        IntMap.singleton 0 (\_ -> modifyIORef' ref (+ 1)))
      dispatchPermissionResult ps 0 42
      count <- readIORef ref
      count @?= 0

  , testCase "multiple simultaneous pending requests dispatch independently" $ do
      -- Uses (appPermissionState globalAppState) — desktop stub auto-grants synchronously
      refA <- newIORef (Nothing :: Maybe PermissionStatus)
      refB <- newIORef (Nothing :: Maybe PermissionStatus)
      requestPermission (appPermissionState globalAppState) PermissionCamera
        (\status -> modifyIORef' refA (const (Just status)))
      requestPermission (appPermissionState globalAppState) PermissionContacts
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

-- | Helper: reset the global error state and restore the default mobileApp.
resetErrorState :: IO ()
resetErrorState = do
  writeIORef (appErrorState globalAppState) Nothing
  runMobileApp mobileApp

-- | Tests for the default exception handler that wraps FFI entry points.
-- Uses 'sequentialTestGroup' because these tests share global mutable state
-- (appErrorState, mobileApp registration) that would conflict with other tests.
exceptionHandlerTests :: TestTree
exceptionHandlerTests = sequentialTestGroup "ExceptionHandler" AllFinish
  [ testCase "exception in maView is caught and error state set" $ do
      resetErrorState
      let crashingApp = MobileApp
            { maContext = defaultMobileContext
            , maView    = throwIO (userError "test-boom")
            }
      runMobileApp crashingApp
      haskellRenderUI nullPtr
      errorState <- readIORef (appErrorState globalAppState)
      case errorState of
        Nothing  -> assertFailure "expected error state to be set"
        Just exc -> assertBool "exception should contain test-boom" ("test-boom" `isInfixOf` show exc)
      resetErrorState

  , testCase "exception in button callback is caught" $ do
      resetErrorState
      ref <- newIORef False
      let crashingApp = MobileApp
            { maContext = defaultMobileContext
            , maView    = pure $ Button ButtonConfig
                { bcLabel  = "crash"
                , bcAction = do
                    writeIORef ref True
                    throwIO (userError "button-boom")
                , bcFontConfig = Nothing
                }
            }
      runMobileApp crashingApp
      -- First render to register the button callback
      haskellRenderUI nullPtr
      -- Reset error state from any render issues, then dispatch
      writeIORef (appErrorState globalAppState) Nothing
      haskellOnUIEvent nullPtr 0
      errorState <- readIORef (appErrorState globalAppState)
      case errorState of
        Nothing  -> assertFailure "expected error state to be set after button callback exception"
        Just exc -> assertBool "exception should contain button-boom" ("button-boom" `isInfixOf` show exc)
      resetErrorState

  , testCase "dismiss clears error and re-renders normal view" $ do
      resetErrorState
      -- Trigger an error first
      let crashingApp = MobileApp
            { maContext = defaultMobileContext
            , maView    = throwIO (userError "dismiss-test")
            }
      runMobileApp crashingApp
      haskellRenderUI nullPtr
      errorState <- readIORef (appErrorState globalAppState)
      assertBool "error state should be set" (case errorState of Just _ -> True; Nothing -> False)
      -- Now restore a good app and dismiss
      runMobileApp mobileApp
      dismissError
      clearedState <- readIORef (appErrorState globalAppState)
      assertBool "error state should be Nothing after dismiss" (case clearedState of Nothing -> True; Just _ -> False)
      -- Re-render should succeed without error
      haskellRenderUI nullPtr
      finalState <- readIORef (appErrorState globalAppState)
      assertBool "error state should remain Nothing after re-render" (case finalState of Nothing -> True; Just _ -> False)
      resetErrorState

  , testCase "onError callback fires on exception" $ do
      resetErrorState
      ref <- newIORef (Nothing :: Maybe String)
      let ctx = MobileContext
            { onLifecycle = \_ -> pure ()
            , onError     = \exc -> writeIORef ref (Just (show exc))
            }
          crashingApp = MobileApp
            { maContext = ctx
            , maView    = throwIO (userError "onError-test")
            }
      runMobileApp crashingApp
      haskellRenderUI nullPtr
      firedValue <- readIORef ref
      case firedValue of
        Nothing  -> assertFailure "onError callback should have been fired"
        Just msg -> assertBool "onError should receive the exception" ("onError-test" `isInfixOf` msg)
      resetErrorState

  , testCase "exception in onError does not crash" $ do
      resetErrorState
      let ctx = MobileContext
            { onLifecycle = \_ -> pure ()
            , onError     = \_ -> throwIO (userError "secondary-boom")
            }
          crashingApp = MobileApp
            { maContext = ctx
            , maView    = throwIO (userError "primary-boom")
            }
      runMobileApp crashingApp
      -- Should not crash despite both maView and onError throwing
      result <- try @IOException (haskellRenderUI nullPtr)
      case result of
        Left exc -> assertFailure ("haskellRenderUI should not throw, but got: " ++ show exc)
        Right () -> pure ()
      resetErrorState

  , testCase "exception in lifecycle handler is caught" $ do
      let crashingCtx = MobileContext
            { onLifecycle = \_ -> throwIO (userError "lifecycle-boom")
            , onError     = \_ -> pure ()
            }
      sptr <- newMobileContext crashingCtx
      let ptr = castStablePtrToPtr sptr
      -- Should not crash
      result <- try @IOException (haskellOnLifecycle ptr 0)
      case result of
        Left exc -> assertFailure ("haskellOnLifecycle should not throw, but got: " ++ show exc)
        Right () -> pure ()
      freeMobileContext sptr
  ]

