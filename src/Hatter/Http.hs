{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE OverloadedStrings #-}
-- | Native HTTP request API for mobile platforms.
--
-- Provides a callback-based API for making HTTP requests using the
-- platform's built-in HTTP stack (HttpURLConnection on Android,
-- NSURLSession on iOS), eliminating the need for Haskell HTTP/TLS
-- dependencies that bloat the binary.
--
-- Platform implementations:
--   * Android: @HttpURLConnection@ on background thread
--   * iOS: @NSURLSession.dataTask@
--   * watchOS: @NSURLSession.dataTask@
--   * Desktop: stub returns 200 OK with empty body synchronously
--
-- The callback registry follows the same sequential 'IORef' 'Int32'
-- pattern used by "Hatter.Dialog" and "Hatter.AuthSession".
module Hatter.Http
  ( HttpMethod(..)
  , HttpRequest(..)
  , HttpResponse(..)
  , HttpError(..)
  , HttpState(..)
  , newHttpState
  , httpMethodToInt
  , performRequest
  , serializeHeaders
  , parseHeaders
  , dispatchHttpResult
  )
where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.IORef (IORef, newIORef, readIORef, writeIORef, modifyIORef')
import Data.Int (Int32)
import Data.IntMap.Strict (IntMap)
import Data.IntMap.Strict qualified as IntMap
import Data.Text (Text)
import Data.Text qualified as Text
import Foreign.C.String (CString, withCString)
import Foreign.C.Types (CInt(..))
import Foreign.Ptr (Ptr, nullPtr)
import System.IO (hPutStrLn, stderr)

-- | HTTP request method.
data HttpMethod
  = HttpGet
  | HttpPost
  | HttpPut
  | HttpDelete
  deriving (Show, Eq)

-- | An HTTP request to be performed by the native platform.
data HttpRequest = HttpRequest
  { hrMethod  :: HttpMethod
  , hrUrl     :: Text
  , hrHeaders :: [(Text, Text)]
  , hrBody    :: ByteString
  } deriving (Show, Eq)

-- | A successful HTTP response from the native platform.
data HttpResponse = HttpResponse
  { hrStatusCode   :: Int
  , hrRespHeaders  :: [(Text, Text)]
  , hrRespBody     :: ByteString
  } deriving (Show, Eq)

-- | HTTP request error.
data HttpError
  = HttpNetworkError Text
  | HttpTimeout
  deriving (Show, Eq)

-- | Mutable state for the HTTP callback registry.
data HttpState = HttpState
  { hsCallbacks  :: IORef (IntMap (Either HttpError HttpResponse -> IO ()))
    -- ^ Map from requestId -> HTTP result callback
  , hsNextId     :: IORef Int32
    -- ^ Next available request ID
  , hsContextPtr :: IORef (Ptr ())
    -- ^ Opaque context pointer passed to the C bridge.
    -- Set by 'AppContext.newAppContext' after the 'StablePtr' is created.
  }

-- | Create a fresh 'HttpState' with no pending callbacks.
-- The context pointer is initially null and must be set via
-- 'hsContextPtr' before calling 'performRequest'.
newHttpState :: IO HttpState
newHttpState = do
  callbacks  <- newIORef IntMap.empty
  nextId     <- newIORef 0
  contextPtr <- newIORef nullPtr
  pure HttpState
    { hsCallbacks  = callbacks
    , hsNextId     = nextId
    , hsContextPtr = contextPtr
    }

-- | Convert an 'HttpMethod' to its C bridge integer code.
httpMethodToInt :: HttpMethod -> CInt
httpMethodToInt HttpGet    = 0
httpMethodToInt HttpPost   = 1
httpMethodToInt HttpPut    = 2
httpMethodToInt HttpDelete = 3

-- | Serialize headers as newline-delimited @Key: Value\\n@ string.
-- HTTP headers cannot contain literal newlines, so this is unambiguous.
serializeHeaders :: [(Text, Text)] -> Text
serializeHeaders = Text.concat . map (\(key, value) -> key <> ": " <> value <> "\n")

-- | Parse newline-delimited @Key: Value\\n@ headers back to pairs.
-- Skips malformed lines (those without @: @).
parseHeaders :: Text -> [(Text, Text)]
parseHeaders headerText =
  [ (Text.strip key, Text.strip value)
  | line <- Text.lines headerText
  , not (Text.null line)
  , let (key, rest) = Text.breakOn ": " line
  , not (Text.null rest)
  , let value = Text.drop 2 rest
  ]

-- | Perform an HTTP request via the native platform bridge.
-- Registers @callback@ and calls the C bridge. The callback fires
-- when the request completes (or synchronously on desktop via the stub).
performRequest :: HttpState -> HttpRequest -> (Either HttpError HttpResponse -> IO ()) -> IO ()
performRequest httpState request callback = do
  requestId <- readIORef (hsNextId httpState)
  modifyIORef' (hsCallbacks httpState) (IntMap.insert (fromIntegral requestId) callback)
  writeIORef (hsNextId httpState) (requestId + 1)
  ctx <- readIORef (hsContextPtr httpState)
  let methodInt = httpMethodToInt (hrMethod request)
      headerStr = Text.unpack (serializeHeaders (hrHeaders request))
  withCString (Text.unpack (hrUrl request)) $ \cUrl ->
    withCString headerStr $ \cHeaders ->
      BS.useAsCStringLen (hrBody request) $ \(cBody, bodyLen) ->
        c_httpRequest ctx (fromIntegral requestId) methodInt
                      cUrl cHeaders cBody (fromIntegral bodyLen)

-- | Dispatch an HTTP result from the platform back to the registered
-- Haskell callback. Removes the callback after firing.
-- Unknown request IDs or result codes are silently logged to stderr.
dispatchHttpResult :: HttpState -> CInt -> CInt -> CInt -> Maybe Text -> ByteString -> IO ()
dispatchHttpResult httpState requestId resultCode httpStatus maybeHeaders responseBody = do
  let reqKey = fromIntegral requestId
  callbacks <- readIORef (hsCallbacks httpState)
  case IntMap.lookup reqKey callbacks of
    Just callback -> do
      modifyIORef' (hsCallbacks httpState) (IntMap.delete reqKey)
      let result = case resultCode of
            0 -> Right HttpResponse
              { hrStatusCode  = fromIntegral httpStatus
              , hrRespHeaders = maybe [] parseHeaders maybeHeaders
              , hrRespBody    = responseBody
              }
            1 -> Left (HttpNetworkError (maybe "" id maybeHeaders))
            2 -> Left HttpTimeout
            _ -> Left (HttpNetworkError ("unknown result code: " <> Text.pack (show resultCode)))
      callback result
    Nothing -> hPutStrLn stderr $
      "dispatchHttpResult: unknown request ID " ++ show requestId

-- | FFI import: send an HTTP request via the C bridge.
foreign import ccall "http_request"
  c_httpRequest :: Ptr () -> CInt -> CInt -> CString -> CString
                -> CString -> CInt -> IO ()
