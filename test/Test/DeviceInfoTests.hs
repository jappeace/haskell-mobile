{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE OverloadedStrings #-}
-- | Unit tests for the device info bridge.
module Test.DeviceInfoTests
  ( deviceInfoTests
  ) where

import Test.Tasty
import Test.Tasty.HUnit

import Foreign.C.String (CString, newCString)
import Hatter.DeviceInfo (DeviceInfo(..), getDeviceInfo)

foreign import ccall "setDeviceModel" c_setDeviceModel :: CString -> IO ()
foreign import ccall "setDeviceOsVersion" c_setDeviceOsVersion :: CString -> IO ()
foreign import ccall "setDeviceScreenDensity" c_setDeviceScreenDensity :: CString -> IO ()
foreign import ccall "setDeviceScreenWidth" c_setDeviceScreenWidth :: CString -> IO ()
foreign import ccall "setDeviceScreenHeight" c_setDeviceScreenHeight :: CString -> IO ()

-- | Tests run sequentially because they mutate process-wide C globals.
deviceInfoTests :: TestTree
deviceInfoTests = sequentialTestGroup "DeviceInfo" AllFinish
  [ testCase "getDeviceInfo returns desktop fallbacks by default" $ do
      info <- getDeviceInfo
      diModel info @?= "desktop"
      diOsVersion info @?= "unknown"
      diScreenDensity info @?= 1.0
      diScreenWidth info @?= 0
      diScreenHeight info @?= 0
  , testCase "setDevice* / getDeviceInfo roundtrip" $ do
      cmodel   <- newCString "Pixel 7"
      cosver   <- newCString "14"
      cdensity <- newCString "2.75"
      cwidth   <- newCString "1080"
      cheight  <- newCString "2400"
      c_setDeviceModel cmodel
      c_setDeviceOsVersion cosver
      c_setDeviceScreenDensity cdensity
      c_setDeviceScreenWidth cwidth
      c_setDeviceScreenHeight cheight
      info <- getDeviceInfo
      diModel info @?= "Pixel 7"
      diOsVersion info @?= "14"
      diScreenDensity info @?= 2.75
      diScreenWidth info @?= 1080
      diScreenHeight info @?= 2400
  , testCase "numeric fields are parsed after setting" $ do
      info <- getDeviceInfo
      assertBool "screenDensity should be positive" (diScreenDensity info > 0)
      assertBool "screenWidth should be positive" (diScreenWidth info > 0)
      assertBool "screenHeight should be positive" (diScreenHeight info > 0)
  ]
