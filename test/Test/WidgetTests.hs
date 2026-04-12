-- | Widget rendering and callback dispatch tests:
-- UI, ScrollView, TextInput, Image, WebView, Styled, TextAlignment, Colors.
module Test.WidgetTests
  ( uiTests
  , scrollViewTests
  , textInputTests
  , imageTests
  , webViewTests
  , mapViewTests
  , styledTests
  , textAlignTests
  , colorTests
  ) where

import Test.Tasty
import Test.Tasty.HUnit

import Data.ByteString qualified as BS
import Data.IORef (newIORef, readIORef, modifyIORef')
import HaskellMobile
  ( MobileApp(..)
  , UserState(..)
  , Action(..)
  , OnChange(..)
  , createAction
  , createOnChange
  )
import HaskellMobile.Widget
  ( ButtonConfig(..)
  , Color(..)
  , FontConfig(..)
  , ImageConfig(..)
  , ImageSource(..)
  , InputType(..)
  , MapViewConfig(..)
  , ResourceName(..)
  , ScaleType(..)
  , TextAlignment(..)
  , TextConfig(..)
  , TextInputConfig(..)
  , WebViewConfig(..)
  , Widget(..)
  , WidgetStyle(..)
  , colorFromText
  , colorToHex
  , defaultStyle
  )
import HaskellMobile.Render (renderWidget, dispatchEvent, dispatchTextEvent)
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
import Test.Helpers (withActions, testApp)

uiTests :: TestTree
uiTests = testGroup "UI"
  [ testCase "callback dispatch fires registered action" $ do
      ref <- newIORef (0 :: Int)
      (clickHandle, rs) <- withActions $
        createAction (modifyIORef' ref (+ 1))
      let widget = Button ButtonConfig
            { bcLabel = "click me", bcAction = clickHandle, bcFontConfig = Nothing }
      renderWidget rs widget
      dispatchEvent rs (actionId clickHandle)
      count <- readIORef ref
      count @?= 1

  , testCase "multiple callbacks each fire independently" $ do
      refA <- newIORef False
      refB <- newIORef False
      ((handleA, handleB), rs) <- withActions $ do
        hA <- createAction (modifyIORef' refA (const True))
        hB <- createAction (modifyIORef' refB (const True))
        pure (hA, hB)
      let widget = Row
            [ Button ButtonConfig
                { bcLabel = "A", bcAction = handleA, bcFontConfig = Nothing }
            , Button ButtonConfig
                { bcLabel = "B", bcAction = handleB, bcFontConfig = Nothing }
            ]
      renderWidget rs widget
      -- Only fire A
      dispatchEvent rs (actionId handleA)
      a <- readIORef refA
      b <- readIORef refB
      a @?= True
      b @?= False
      -- Now fire B
      dispatchEvent rs (actionId handleB)
      b' <- readIORef refB
      b' @?= True

  , testCase "re-render preserves callback handles" $ do
      ref <- newIORef (0 :: Int)
      (clickHandle, rs) <- withActions $
        createAction (modifyIORef' ref (+ 1))
      -- First render
      renderWidget rs (Button ButtonConfig
        { bcLabel = "old", bcAction = clickHandle, bcFontConfig = Nothing })
      -- Second render (same handle)
      renderWidget rs (Button ButtonConfig
        { bcLabel = "new", bcAction = clickHandle, bcFontConfig = Nothing })
      dispatchEvent rs (actionId clickHandle)
      count <- readIORef ref
      count @?= 1

  , testCase "dispatching unknown callback ID logs error" $ do
      ((), rs) <- withActions (pure ())
      renderWidget rs (Text TextConfig { tcLabel = "no buttons", tcFontConfig = Nothing })
      -- Should not throw (logs to stderr)
      dispatchEvent rs 42
      dispatchEvent rs 999

  , testCase "nested widget tree renders without error" $ do
      ((handleA, handleB), rs) <- withActions $ do
        hA <- createAction (pure ())
        hB <- createAction (pure ())
        pure (hA, hB)
      let widget = Column
            [ Text TextConfig { tcLabel = "header", tcFontConfig = Nothing }
            , Row
              [ Button ButtonConfig
                  { bcLabel = "a", bcAction = handleA, bcFontConfig = Nothing }
              , Column
                [ Text TextConfig { tcLabel = "nested", tcFontConfig = Nothing }
                , Button ButtonConfig
                    { bcLabel = "b", bcAction = handleB, bcFontConfig = Nothing }
                ]
              ]
            , Text TextConfig { tcLabel = "footer", tcFontConfig = Nothing }
            ]
      -- Should not throw — exercises all node types
      renderWidget rs widget

  , testCase "testApp view returns a widget" $ do
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
      app <- testApp
      widget <- maView app dummyUserState
      -- testApp returns a Text widget
      case widget of
        Text _          -> pure ()
        Column _        -> assertFailure "expected Text, got Column"
        Button _        -> assertFailure "expected Text, got Button"
        TextInput _     -> assertFailure "expected Text, got TextInput"
        Image _         -> assertFailure "expected Text, got Image"
        WebView _       -> assertFailure "expected Text, got WebView"
        MapView _       -> assertFailure "expected Text, got MapView"
        Row _           -> assertFailure "expected Text, got Row"
        ScrollView _    -> assertFailure "expected Text, got ScrollView"
        Styled _ _      -> assertFailure "expected Text, got Styled"
        Animated _ _    -> assertFailure "expected Text, got Animated"
  ]

-- | Tests for the ScrollView widget binding.
-- These exercise the Haskell render path shared by both Android and iOS —
-- the platform bridge (JNI / UIKit) receives UI_NODE_SCROLL_VIEW (5) and
-- is responsible for mapping it to a native scroll container.
scrollViewTests :: TestTree
scrollViewTests = testGroup "ScrollView"
  [ testCase "ScrollView renders without error" $ do
      ((), rs) <- withActions (pure ())
      renderWidget rs (ScrollView
        [ Text TextConfig { tcLabel = "item 1", tcFontConfig = Nothing }
        , Text TextConfig { tcLabel = "item 2", tcFontConfig = Nothing }
        ])

  , testCase "button inside ScrollView fires its callback" $ do
      ref <- newIORef (0 :: Int)
      (clickHandle, rs) <- withActions $
        createAction (modifyIORef' ref (+ 1))
      renderWidget rs $ ScrollView
        [ Button ButtonConfig
            { bcLabel = "press me", bcAction = clickHandle, bcFontConfig = Nothing } ]
      dispatchEvent rs (actionId clickHandle)
      count <- readIORef ref
      count @?= 1

  , testCase "ScrollView with nested Column renders and dispatches correctly" $ do
      ref <- newIORef False
      (clickHandle, rs) <- withActions $
        createAction (modifyIORef' ref (const True))
      renderWidget rs $ ScrollView
        [ Column
          [ Text TextConfig { tcLabel = "header", tcFontConfig = Nothing }
          , Button ButtonConfig
              { bcLabel = "action", bcAction = clickHandle, bcFontConfig = Nothing }
          ]
        ]
      dispatchEvent rs (actionId clickHandle)
      fired <- readIORef ref
      fired @?= True

  , testCase "re-render inside ScrollView preserves callbacks" $ do
      ref <- newIORef (0 :: Int)
      (clickHandle, rs) <- withActions $
        createAction (modifyIORef' ref (+ 1))
      renderWidget rs $ ScrollView [Button ButtonConfig
        { bcLabel = "old", bcAction = clickHandle, bcFontConfig = Nothing }]
      renderWidget rs $ ScrollView [Button ButtonConfig
        { bcLabel = "new", bcAction = clickHandle, bcFontConfig = Nothing }]
      dispatchEvent rs (actionId clickHandle)
      count <- readIORef ref
      count @?= 1
  ]

textInputTests :: TestTree
textInputTests = testGroup "TextInput"
  [ testCase "text callback fires with correct value" $ do
      ref <- newIORef ("" :: String)
      (changeHandle, rs) <- withActions $
        createOnChange (\t -> modifyIORef' ref (const (show t)))
      let widget = TextInput TextInputConfig
            { tiInputType = InputText, tiHint = "hint", tiValue = ""
            , tiOnChange = changeHandle
            , tiFontConfig = Nothing }
      renderWidget rs widget
      dispatchTextEvent rs (onChangeId changeHandle) "hello"
      val <- readIORef ref
      val @?= show ("hello" :: String)

  , testCase "text callback receives updated value" $ do
      ref <- newIORef ("" :: String)
      (changeHandle, rs) <- withActions $
        createOnChange (\t -> modifyIORef' ref (const (show t)))
      let widget = TextInput TextInputConfig
            { tiInputType = InputText, tiHint = "enter weight", tiValue = "80"
            , tiOnChange = changeHandle
            , tiFontConfig = Nothing }
      renderWidget rs widget
      dispatchTextEvent rs (onChangeId changeHandle) "95.5"
      val <- readIORef ref
      val @?= show ("95.5" :: String)

  , testCase "dispatchTextEvent with unknown ID does not crash" $ do
      ((), rs) <- withActions (pure ())
      renderWidget rs (Text TextConfig { tcLabel = "no inputs", tcFontConfig = Nothing })
      -- Should not throw
      dispatchTextEvent rs 42 "ignored"
      dispatchTextEvent rs 999 "also ignored"

  , testCase "text and click callbacks share ID space without collision" $ do
      clickRef <- newIORef False
      textRef  <- newIORef ("" :: String)
      ((clickHandle, changeHandle), rs) <- withActions $ do
        ch <- createAction (modifyIORef' clickRef (const True))
        th <- createOnChange (\t -> modifyIORef' textRef (const (show t)))
        pure (ch, th)
      let widget = Column
            [ Button ButtonConfig
                { bcLabel = "ok", bcAction = clickHandle, bcFontConfig = Nothing }
            , TextInput TextInputConfig
                { tiInputType = InputText, tiHint = "hint", tiValue = ""
                , tiOnChange = changeHandle
                , tiFontConfig = Nothing }
            ]
      renderWidget rs widget
      dispatchEvent rs (actionId clickHandle)
      dispatchTextEvent rs (onChangeId changeHandle) "typed"
      click <- readIORef clickRef
      text  <- readIORef textRef
      click @?= True
      text  @?= show ("typed" :: String)

  , testCase "re-render preserves text callbacks" $ do
      ref <- newIORef ("" :: String)
      (changeHandle, rs) <- withActions $
        createOnChange (\t -> modifyIORef' ref (const (show t)))
      renderWidget rs $ TextInput TextInputConfig
        { tiInputType = InputText, tiHint = "old", tiValue = ""
        , tiOnChange = changeHandle
        , tiFontConfig = Nothing }
      renderWidget rs $ TextInput TextInputConfig
        { tiInputType = InputText, tiHint = "new", tiValue = ""
        , tiOnChange = changeHandle
        , tiFontConfig = Nothing }
      dispatchTextEvent rs (onChangeId changeHandle) "val"
      val <- readIORef ref
      val @?= show ("val" :: String)

  , testCase "InputNumber callback fires correctly" $ do
      ref <- newIORef ("" :: String)
      (changeHandle, rs) <- withActions $
        createOnChange (\t -> modifyIORef' ref (const (show t)))
      let widget = TextInput TextInputConfig
            { tiInputType = InputNumber, tiHint = "weight", tiValue = ""
            , tiOnChange = changeHandle
            , tiFontConfig = Nothing }
      renderWidget rs widget
      dispatchTextEvent rs (onChangeId changeHandle) "72.5"
      val <- readIORef ref
      val @?= show ("72.5" :: String)

  , testCase "InputText and InputNumber coexist with independent callbacks" $ do
      textRef   <- newIORef ("" :: String)
      numberRef <- newIORef ("" :: String)
      ((textHandle, numberHandle), rs) <- withActions $ do
        th <- createOnChange (\t -> modifyIORef' textRef (const (show t)))
        nh <- createOnChange (\t -> modifyIORef' numberRef (const (show t)))
        pure (th, nh)
      let widget = Column
            [ TextInput TextInputConfig
                { tiInputType = InputText, tiHint = "name", tiValue = ""
                , tiOnChange = textHandle
                , tiFontConfig = Nothing }
            , TextInput TextInputConfig
                { tiInputType = InputNumber, tiHint = "weight", tiValue = ""
                , tiOnChange = numberHandle
                , tiFontConfig = Nothing }
            ]
      renderWidget rs widget
      dispatchTextEvent rs (onChangeId textHandle) "Alice"
      dispatchTextEvent rs (onChangeId numberHandle) "60.0"
      tVal <- readIORef textRef
      nVal <- readIORef numberRef
      tVal @?= show ("Alice" :: String)
      nVal @?= show ("60.0" :: String)
  ]

-- | Tests for the Image widget binding.
imageTests :: TestTree
imageTests = testGroup "Image"
  [ testCase "Image with resource renders without error" $ do
      ((), rs) <- withActions (pure ())
      renderWidget rs $ Image ImageConfig
        { icSource = ImageResource (ResourceName "ic_launcher"), icScaleType = ScaleFit }

  , testCase "Image with ByteString data renders without error" $ do
      ((), rs) <- withActions (pure ())
      let bytes = BS.pack [0x89, 0x50, 0x4E, 0x47, 0x00, 0x00, 0x00, 0x00]
      renderWidget rs $ Image ImageConfig
        { icSource = ImageData bytes, icScaleType = ScaleFill }

  , testCase "Image with file path renders without error" $ do
      ((), rs) <- withActions (pure ())
      renderWidget rs $ Image ImageConfig
        { icSource = ImageFile "/nonexistent/test.png", icScaleType = ScaleNone }

  , testCase "Image inside Column renders" $ do
      ((), rs) <- withActions (pure ())
      renderWidget rs $ Column
        [ Text TextConfig { tcLabel = "header", tcFontConfig = Nothing }
        , Image ImageConfig
            { icSource = ImageResource (ResourceName "logo"), icScaleType = ScaleFit }
        ]

  , testCase "Styled Image renders without error" $ do
      ((), rs) <- withActions (pure ())
      renderWidget rs $ Styled defaultStyle
        (Image ImageConfig
          { icSource = ImageResource (ResourceName "icon"), icScaleType = ScaleNone })

  , testCase "ScaleFit renders without error" $ do
      ((), rs) <- withActions (pure ())
      renderWidget rs $ Image ImageConfig
        { icSource = ImageResource (ResourceName "fit_test"), icScaleType = ScaleFit }

  , testCase "ScaleFill renders without error" $ do
      ((), rs) <- withActions (pure ())
      renderWidget rs $ Image ImageConfig
        { icSource = ImageResource (ResourceName "fill_test"), icScaleType = ScaleFill }

  , testCase "ScaleNone renders without error" $ do
      ((), rs) <- withActions (pure ())
      renderWidget rs $ Image ImageConfig
        { icSource = ImageResource (ResourceName "none_test"), icScaleType = ScaleNone }
  ]

-- | Tests for the WebView widget.
webViewTests :: TestTree
webViewTests = testGroup "WebView"
  [ testCase "WebView renders without error" $ do
      ((), rs) <- withActions (pure ())
      renderWidget rs $ WebView WebViewConfig
        { wvUrl = "https://example.com", wvOnPageLoad = Nothing }

  , testCase "WebView with callback registers handler and fires" $ do
      ref <- newIORef (0 :: Int)
      (pageLoadHandle, rs) <- withActions $
        createAction (modifyIORef' ref (+ 1))
      renderWidget rs $ WebView WebViewConfig
        { wvUrl = "https://example.com"
        , wvOnPageLoad = Just pageLoadHandle
        }
      dispatchEvent rs (actionId pageLoadHandle)
      count <- readIORef ref
      count @?= 1

  , testCase "WebView without callback does not register handler" $ do
      ((), rs) <- withActions (pure ())
      renderWidget rs $ WebView WebViewConfig
        { wvUrl = "https://example.com", wvOnPageLoad = Nothing }
      -- No callbacks registered, dispatching should log error but not crash
      dispatchEvent rs 0

  , testCase "WebView inside Column renders" $ do
      ((), rs) <- withActions (pure ())
      renderWidget rs $ Column
        [ Text TextConfig { tcLabel = "header", tcFontConfig = Nothing }
        , WebView WebViewConfig
            { wvUrl = "https://example.com", wvOnPageLoad = Nothing }
        ]

  , testCase "Styled WebView renders without error" $ do
      ((), rs) <- withActions (pure ())
      renderWidget rs $ Styled defaultStyle
        (WebView WebViewConfig
          { wvUrl = "https://example.com", wvOnPageLoad = Nothing })
  ]

-- | Tests for the Styled widget wrapper.
styledTests :: TestTree
styledTests = testGroup "Styled"
  [ testCase "Styled Text renders without error" $ do
      ((), rs) <- withActions (pure ())
      renderWidget rs $ Styled (WidgetStyle (Just 8.0) Nothing Nothing Nothing)
        (Text TextConfig { tcLabel = "styled", tcFontConfig = Just (FontConfig 20.0) })

  , testCase "Styled Button fires callback" $ do
      ref <- newIORef (0 :: Int)
      (clickHandle, rs) <- withActions $
        createAction (modifyIORef' ref (+ 1))
      renderWidget rs $ Styled (WidgetStyle Nothing Nothing Nothing Nothing)
        (Button ButtonConfig
          { bcLabel = "tap", bcAction = clickHandle
          , bcFontConfig = Just (FontConfig 16.0) })
      dispatchEvent rs (actionId clickHandle)
      count <- readIORef ref
      count @?= 1

  , testCase "Styled Column renders children and dispatches" $ do
      ref <- newIORef False
      (clickHandle, rs) <- withActions $
        createAction (modifyIORef' ref (const True))
      renderWidget rs $ Styled defaultStyle
        (Column [ Text TextConfig { tcLabel = "info", tcFontConfig = Nothing }
                , Button ButtonConfig
                    { bcLabel = "go", bcAction = clickHandle, bcFontConfig = Nothing }
                ])
      dispatchEvent rs (actionId clickHandle)
      fired <- readIORef ref
      fired @?= True

  , testCase "nested Styled applies both styles" $ do
      ((), rs) <- withActions (pure ())
      renderWidget rs $
        Styled (WidgetStyle (Just 12.0) Nothing Nothing Nothing)
          (Styled (WidgetStyle Nothing Nothing Nothing Nothing)
            (Text TextConfig { tcLabel = "double styled", tcFontConfig = Just (FontConfig 18.0) }))

  , testCase "defaultStyle is a no-op" $ do
      ((), rs) <- withActions (pure ())
      renderWidget rs $ Styled defaultStyle
        (Text TextConfig { tcLabel = "plain", tcFontConfig = Nothing })

  , testCase "re-render preserves callbacks through Styled" $ do
      ref <- newIORef (0 :: Int)
      (clickHandle, rs) <- withActions $
        createAction (modifyIORef' ref (+ 1))
      renderWidget rs $ Styled defaultStyle
        (Button ButtonConfig
          { bcLabel = "old", bcAction = clickHandle, bcFontConfig = Nothing })
      renderWidget rs $ Styled defaultStyle
        (Button ButtonConfig
          { bcLabel = "new", bcAction = clickHandle, bcFontConfig = Nothing })
      dispatchEvent rs (actionId clickHandle)
      count <- readIORef ref
      count @?= 1
  ]

-- | Tests for TextAlignment support in Styled widgets.
textAlignTests :: TestTree
textAlignTests = testGroup "TextAlignment"
  [ testCase "Styled with AlignCenter renders without error" $ do
      ((), rs) <- withActions (pure ())
      renderWidget rs $ Styled (WidgetStyle Nothing (Just AlignCenter) Nothing Nothing)
        (Text TextConfig { tcLabel = "centered", tcFontConfig = Nothing })

  , testCase "Styled with AlignCenter on Button fires callback" $ do
      ref <- newIORef (0 :: Int)
      (clickHandle, rs) <- withActions $
        createAction (modifyIORef' ref (+ 1))
      renderWidget rs $ Styled (WidgetStyle Nothing (Just AlignCenter) Nothing Nothing)
        (Button ButtonConfig
          { bcLabel = "tap", bcAction = clickHandle, bcFontConfig = Nothing })
      dispatchEvent rs (actionId clickHandle)
      count <- readIORef ref
      count @?= 1

  , testCase "defaultStyle has no text alignment" $
      wsTextAlign defaultStyle @?= Nothing

  , testCase "Styled with AlignEnd renders without error" $ do
      ((), rs) <- withActions (pure ())
      renderWidget rs $ Styled (WidgetStyle Nothing (Just AlignEnd) Nothing Nothing)
        (Text TextConfig { tcLabel = "end aligned", tcFontConfig = Nothing })
  ]

-- | Tests for color support in Styled widgets.
colorTests :: TestTree
colorTests = testGroup "Colors"
  [ testCase "Styled with textColor renders and callback fires" $ do
      ref <- newIORef (0 :: Int)
      (clickHandle, rs) <- withActions $
        createAction (modifyIORef' ref (+ 1))
      renderWidget rs $ Styled (WidgetStyle Nothing Nothing (Just (Color 255 0 0 255)) Nothing)
        (Button ButtonConfig
          { bcLabel = "red", bcAction = clickHandle, bcFontConfig = Nothing })
      dispatchEvent rs (actionId clickHandle)
      count <- readIORef ref
      count @?= 1

  , testCase "Styled with backgroundColor renders without error" $ do
      ((), rs) <- withActions (pure ())
      renderWidget rs $ Styled (WidgetStyle Nothing Nothing Nothing (Just (Color 0 255 0 255)))
        (Text TextConfig { tcLabel = "green bg", tcFontConfig = Nothing })

  , testCase "both textColor and backgroundColor together" $ do
      ref <- newIORef (0 :: Int)
      (clickHandle, rs) <- withActions $
        createAction (modifyIORef' ref (+ 1))
      renderWidget rs $ Styled (WidgetStyle Nothing Nothing (Just (Color 255 0 0 255)) (Just (Color 0 255 0 255)))
        (Button ButtonConfig
          { bcLabel = "colored", bcAction = clickHandle, bcFontConfig = Nothing })
      dispatchEvent rs (actionId clickHandle)
      count <- readIORef ref
      count @?= 1

  , testCase "defaultStyle has no colors" $ do
      wsTextColor defaultStyle @?= Nothing
      wsBackgroundColor defaultStyle @?= Nothing

  , testCase "nested Styled with different colors renders" $ do
      ((), rs) <- withActions (pure ())
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

-- | Tests for the MapView widget.
mapViewTests :: TestTree
mapViewTests = testGroup "MapView"
  [ testCase "MapView renders without error" $ do
      ((), rs) <- withActions (pure ())
      renderWidget rs $ MapView MapViewConfig
        { mvLatitude = 52.3676, mvLongitude = 4.9041
        , mvZoom = 12.0, mvShowUserLocation = False
        , mvOnRegionChange = Nothing
        }

  , testCase "region change callback registered and fires via dispatchTextEvent" $ do
      ref <- newIORef ("" :: String)
      (changeHandle, rs) <- withActions $
        createOnChange (\t -> modifyIORef' ref (const (show t)))
      renderWidget rs $ MapView MapViewConfig
        { mvLatitude = 52.3676, mvLongitude = 4.9041
        , mvZoom = 12.0, mvShowUserLocation = False
        , mvOnRegionChange = Just changeHandle
        }
      dispatchTextEvent rs (onChangeId changeHandle) "51.5074,-0.1278,10.0"
      val <- readIORef ref
      val @?= show ("51.5074,-0.1278,10.0" :: String)

  , testCase "MapView without callback renders cleanly" $ do
      ((), rs) <- withActions (pure ())
      renderWidget rs $ MapView MapViewConfig
        { mvLatitude = 0.0, mvLongitude = 0.0
        , mvZoom = 1.0, mvShowUserLocation = True
        , mvOnRegionChange = Nothing
        }
      -- Dispatching unknown ID should not crash
      dispatchTextEvent rs 999 "ignored"

  , testCase "MapView inside Column renders" $ do
      ((), rs) <- withActions (pure ())
      renderWidget rs $ Column
        [ Text TextConfig { tcLabel = "header", tcFontConfig = Nothing }
        , MapView MapViewConfig
            { mvLatitude = 52.3676, mvLongitude = 4.9041
            , mvZoom = 12.0, mvShowUserLocation = False
            , mvOnRegionChange = Nothing
            }
        ]

  , testCase "re-render preserves region change callback" $ do
      ref <- newIORef ("" :: String)
      (changeHandle, rs) <- withActions $
        createOnChange (\t -> modifyIORef' ref (const (show t)))
      let config = MapViewConfig
            { mvLatitude = 52.3676, mvLongitude = 4.9041
            , mvZoom = 12.0, mvShowUserLocation = False
            , mvOnRegionChange = Just changeHandle
            }
      renderWidget rs $ MapView config
      renderWidget rs $ MapView config { mvZoom = 14.0 }
      dispatchTextEvent rs (onChangeId changeHandle) "52.3676,4.9041,14.0"
      val <- readIORef ref
      val @?= show ("52.3676,4.9041,14.0" :: String)
  ]
