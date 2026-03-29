-- | Core types for the mobile app framework.
-- Separated from "HaskellMobile" so that downstream modules
-- (e.g. "HaskellMobile.App") can import 'MobileApp' without
-- creating an import cycle through the main facade.
module HaskellMobile.Types
  ( MobileApp(..)
  , runMobileApp
  , getMobileApp
  )
where

import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import HaskellMobile.Lifecycle (MobileContext)
import HaskellMobile.Widget (Widget)
import System.IO.Unsafe (unsafePerformIO)

-- | Application definition record. Downstream apps create one of these
-- and register it via 'runMobileApp'.
data MobileApp = MobileApp
  { maContext :: MobileContext
  , maView    :: IO Widget
  }

-- | Global storage for the registered app. Filled by 'runMobileApp'.
globalMobileApp :: IORef (Maybe MobileApp)
globalMobileApp = unsafePerformIO (newIORef Nothing)
{-# NOINLINE globalMobileApp #-}

-- | Register the mobile app. Must be called before any FFI entry point.
-- The user's @main :: IO ()@ calls this to register their app.
runMobileApp :: MobileApp -> IO ()
runMobileApp = writeIORef globalMobileApp . Just

-- | Read the registered app. Errors if 'runMobileApp' was not called.
getMobileApp :: IO MobileApp
getMobileApp = do
  mApp <- readIORef globalMobileApp
  case mApp of
    Just app -> pure app
    Nothing  -> error "haskell-mobile: runMobileApp was not called before FFI entry"
