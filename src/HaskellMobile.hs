{-# LANGUAGE ForeignFunctionInterface #-}
module HaskellMobile
  ( main
  , haskellInit
  , haskellGreet
  , haskellCreateContext
  , appContext
  , LifecycleEvent(..)
  , MobileContext(..)
  , defaultMobileContext
  , loggingMobileContext
  , platformLog
  , newMobileContext
  , freeMobileContext
  )
where

import Foreign.C.String (CString, newCString, peekCString)
import Foreign.Ptr (Ptr)
import Foreign.StablePtr (castStablePtrToPtr)
import HaskellMobile.App (appContext)
import HaskellMobile.Lifecycle
  ( LifecycleEvent(..)
  , MobileContext(..)
  , defaultMobileContext
  , loggingMobileContext
  , platformLog
  , newMobileContext
  , freeMobileContext
  )

main :: IO ()
main = putStrLn "hello, world flaky"

-- | Placeholder for RTS initialization, called from JNI_OnLoad
haskellInit :: IO ()
haskellInit = putStrLn "Haskell RTS initialized"

foreign export ccall haskellInit :: IO ()

-- | Takes a name as CString, returns "Hello from Haskell, <name>!" as CString.
-- Caller is responsible for freeing the returned CString.
haskellGreet :: CString -> IO CString
haskellGreet cname = do
  name <- peekCString cname
  newCString ("Hello from Haskell, " ++ name ++ "!")

foreign export ccall haskellGreet :: CString -> IO CString

-- | Create a default 'MobileContext' and return it as an opaque pointer
-- for C code. Called by platform bridges after 'haskellInit'.
haskellCreateContext :: IO (Ptr ())
haskellCreateContext = castStablePtrToPtr <$> newMobileContext appContext

foreign export ccall haskellCreateContext :: IO (Ptr ())
