{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE OverloadedStrings #-}
module Hatter.DeviceInfo
  ( DeviceInfo(..)
  , getDeviceInfo
  , haskellLogDeviceInfo
  ) where

import Data.Text (Text)
import Data.Text qualified as Text
import Foreign.C.String (CString, peekCString)
import Hatter.Lifecycle (platformLog)
import Text.Read (readMaybe)

-- | Device information collected from the host platform.
data DeviceInfo = DeviceInfo
  { diModel         :: Text    -- ^ Device model name (e.g. @\"Pixel 7\"@, @\"iPhone15,2\"@)
  , diOsVersion     :: Text    -- ^ OS version string (e.g. @\"14\"@, @\"17.0\"@)
  , diScreenDensity :: Double  -- ^ Screen density / scale factor (e.g. @2.75@, @3.0@)
  , diScreenWidth   :: Int     -- ^ Screen width in physical pixels (e.g. @1080@)
  , diScreenHeight  :: Int     -- ^ Screen height in physical pixels (e.g. @2400@)
  } deriving (Show, Eq)

foreign import ccall "getDeviceModel" c_getDeviceModel :: IO CString
foreign import ccall "getDeviceOsVersion" c_getDeviceOsVersion :: IO CString
foreign import ccall "getDeviceScreenDensity" c_getDeviceScreenDensity :: IO CString
foreign import ccall "getDeviceScreenWidth" c_getDeviceScreenWidth :: IO CString
foreign import ccall "getDeviceScreenHeight" c_getDeviceScreenHeight :: IO CString

-- | Query all device information from the host platform.
--
-- * Android: values set from @Build.MODEL@, @Build.VERSION.RELEASE@, @DisplayMetrics@
-- * iOS: values set from @utsname@, @UIDevice@, @UIScreen@
-- * Desktop: returns fallback values (@\"desktop\"@, @\"unknown\"@, @1.0@, @0@, @0@)
getDeviceInfo :: IO DeviceInfo
getDeviceInfo = do
  model         <- peekText =<< c_getDeviceModel
  osVersion     <- peekText =<< c_getDeviceOsVersion
  densityStr    <- peekString =<< c_getDeviceScreenDensity
  widthStr      <- peekString =<< c_getDeviceScreenWidth
  heightStr     <- peekString =<< c_getDeviceScreenHeight
  pure DeviceInfo
    { diModel         = model
    , diOsVersion     = osVersion
    , diScreenDensity = parseDouble densityStr
    , diScreenWidth   = parseInt widthStr
    , diScreenHeight  = parseInt heightStr
    }

-- | Log all device info fields via 'platformLog'.
-- Called from platform bridges after device info setters are invoked.
haskellLogDeviceInfo :: IO ()
haskellLogDeviceInfo = do
  info <- getDeviceInfo
  platformLog ("DeviceInfo model: " <> diModel info)
  platformLog ("DeviceInfo osVersion: " <> diOsVersion info)
  platformLog ("DeviceInfo screenDensity: " <> Text.pack (show (diScreenDensity info)))
  platformLog ("DeviceInfo screenWidth: " <> Text.pack (show (diScreenWidth info)))
  platformLog ("DeviceInfo screenHeight: " <> Text.pack (show (diScreenHeight info)))

foreign export ccall haskellLogDeviceInfo :: IO ()

-- | Peek a CString into Text.
peekText :: CString -> IO Text
peekText cstr = Text.pack <$> peekCString cstr

-- | Peek a CString into String.
peekString :: CString -> IO String
peekString = peekCString

-- | Parse a Double from a string, defaulting to 0.0.
parseDouble :: String -> Double
parseDouble str = case readMaybe str of
  Just value -> value
  Nothing    -> 0.0

-- | Parse an Int from a string, defaulting to 0.
parseInt :: String -> Int
parseInt str = case readMaybe str of
  Just value -> value
  Nothing    -> 0
