module Main where

import Test.Tasty
import Test.Tasty.QuickCheck as QC
import Test.Tasty.HUnit

import Data.Either (isLeft)
import Data.List (sort)
import Data.IORef (newIORef, readIORef, modifyIORef')
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import Foreign.C.String (newCString, peekCString)
import Foreign.Marshal.Alloc (free)
import Foreign.Ptr (Ptr)
import Foreign.StablePtr (castStablePtrToPtr)
import HaskellMobile
  ( MobileApp(..)
  , runMobileApp
  , getMobileApp
  , haskellGreet
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
  , lifecycleFromInt
  , lifecycleToInt
  , loggingMobileContext
  , newMobileContext
  , freeMobileContext
  , haskellOnLifecycle
  )
import HaskellMobile.Widget (Widget(..))
import HaskellMobile.Render (newRenderState, renderWidget, dispatchEvent, dispatchTextEvent)

main :: IO ()
main = do
  -- Register the default app so FFI functions that read the IORef work
  runMobileApp mobileApp
  defaultMain tests

tests :: TestTree
tests = testGroup "Tests" [qcProps, unitTests, lifecycleTests, uiTests, scrollViewTests, textInputTests, registrationTests, localeTests, i18nTests]

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
  sptr <- newMobileContext MobileContext { onLifecycle = callback }
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
      let widget = Button "click me" (modifyIORef' ref (+ 1))
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
            [ Button "A" (modifyIORef' refA (const True))
            , Button "B" (modifyIORef' refB (const True))
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
      renderWidget rs (Button "old" (modifyIORef' refOld (const True)))
      -- Second render replaces it
      renderWidget rs (Button "new" (modifyIORef' refNew (const True)))
      dispatchEvent rs 0
      old <- readIORef refOld
      new <- readIORef refNew
      old @?= False
      new @?= True

  , testCase "dispatching unknown callback ID logs error" $ do
      rs <- newRenderState
      renderWidget rs (Text "no buttons")
      -- Should not throw (logs to stderr)
      dispatchEvent rs 42
      dispatchEvent rs 999

  , testCase "nested widget tree renders without error" $ do
      rs <- newRenderState
      let widget = Column
            [ Text "header"
            , Row
              [ Button "a" (pure ())
              , Column
                [ Text "nested"
                , Button "b" (pure ())
                ]
              ]
            , Text "footer"
            ]
      -- Should not throw — exercises all node types
      renderWidget rs widget

  , testCase "mobileApp view returns a widget" $ do
      widget <- maView mobileApp
      -- mobileApp is the counter demo; verify it's a column
      case widget of
        Column _        -> pure ()
        Text _          -> assertFailure "expected Column, got Text"
        Button _ _      -> assertFailure "expected Column, got Button"
        TextInput _ _ _ -> assertFailure "expected Column, got TextInput"
        Row _           -> assertFailure "expected Column, got Row"
        ScrollView _    -> assertFailure "expected Column, got ScrollView"
  ]

-- | Tests for the ScrollView widget binding.
-- These exercise the Haskell render path shared by both Android and iOS —
-- the platform bridge (JNI / UIKit) receives UI_NODE_SCROLL_VIEW (5) and
-- is responsible for mapping it to a native scroll container.
scrollViewTests :: TestTree
scrollViewTests = testGroup "ScrollView"
  [ testCase "ScrollView renders without error" $ do
      rs <- newRenderState
      renderWidget rs (ScrollView [Text "item 1", Text "item 2"])

  , testCase "button inside ScrollView fires its callback" $ do
      ref <- newIORef (0 :: Int)
      rs <- newRenderState
      renderWidget rs $ ScrollView
        [ Button "press me" (modifyIORef' ref (+ 1)) ]
      dispatchEvent rs 0
      count <- readIORef ref
      count @?= 1

  , testCase "ScrollView with nested Column renders and dispatches correctly" $ do
      ref <- newIORef False
      rs <- newRenderState
      renderWidget rs $ ScrollView
        [ Column
          [ Text "header"
          , Button "action" (modifyIORef' ref (const True))
          ]
        ]
      dispatchEvent rs 0
      fired <- readIORef ref
      fired @?= True

  , testCase "re-render inside ScrollView resets callbacks" $ do
      refOld <- newIORef False
      refNew <- newIORef False
      rs <- newRenderState
      renderWidget rs $ ScrollView [Button "old" (modifyIORef' refOld (const True))]
      renderWidget rs $ ScrollView [Button "new" (modifyIORef' refNew (const True))]
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
      let widget = TextInput "hint" "" (\t -> modifyIORef' ref (const (show t)))
      renderWidget rs widget
      -- Callback 0 is the text change handler
      dispatchTextEvent rs 0 "hello"
      val <- readIORef ref
      val @?= show ("hello" :: String)

  , testCase "text callback receives updated value" $ do
      ref <- newIORef ("" :: String)
      rs <- newRenderState
      let widget = TextInput "enter weight" "80" (\t -> modifyIORef' ref (const (show t)))
      renderWidget rs widget
      dispatchTextEvent rs 0 "95.5"
      val <- readIORef ref
      val @?= show ("95.5" :: String)

  , testCase "dispatchTextEvent with unknown ID does not crash" $ do
      rs <- newRenderState
      renderWidget rs (Text "no inputs")
      -- Should not throw
      dispatchTextEvent rs 42 "ignored"
      dispatchTextEvent rs 999 "also ignored"

  , testCase "text and click callbacks share ID space without collision" $ do
      clickRef <- newIORef False
      textRef  <- newIORef ("" :: String)
      rs <- newRenderState
      let widget = Column
            [ Button "ok" (modifyIORef' clickRef (const True))
            , TextInput "hint" "" (\t -> modifyIORef' textRef (const (show t)))
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
      renderWidget rs (TextInput "old" "" (\t -> modifyIORef' refOld (const (show t))))
      renderWidget rs (TextInput "new" "" (\t -> modifyIORef' refNew (const (show t))))
      dispatchTextEvent rs 0 "val"
      old <- readIORef refOld
      new <- readIORef refNew
      old @?= ""
      new @?= show ("val" :: String)
  ]

-- | Tests for the IORef registration pattern.
registrationTests :: TestTree
registrationTests = testGroup "Registration"
  [ testCase "getMobileApp returns the registered app" $ do
      app <- getMobileApp
      -- The app was registered in main before defaultMain.
      -- Verify it has the same context as mobileApp.
      mapM_ (onLifecycle (maContext app)) [Create, Destroy]

  , testCase "runMobileApp overwrites previous registration" $ do
      let customCtx = MobileContext { onLifecycle = \_ -> pure () }
          customApp = MobileApp { maContext = customCtx, maView = pure (Text "custom") }
      runMobileApp customApp
      app <- getMobileApp
      widget <- maView app
      case widget of
        Text t  -> t @?= "custom"
        _       -> assertFailure "expected Text \"custom\""
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
