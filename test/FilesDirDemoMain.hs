{-# LANGUAGE OverloadedStrings #-}
-- | Mobile entry point for the files-dir-demo test app.
--
-- Used by the emulator and simulator files directory integration tests.
-- After the platform bridge is initialised (via startMobileApp), retrieves
-- the app files directory, writes a test file, reads it back, and logs the
-- result.
module Main where

import Control.Exception (SomeException, try)
import Data.Text (pack)
import Foreign.Ptr (Ptr)
import System.FilePath ((</>))
import HaskellMobile
  ( MobileApp(..)
  , AppContext
  , startMobileApp
  , platformLog
  , getAppFilesDir
  , loggingMobileContext
  , newActionState
  )
import HaskellMobile.Widget (TextConfig(..), Widget(..))

main :: IO (Ptr AppContext)
main = do
  actionState <- newActionState

  -- Start the app first so the platform bridge sets the files dir path.
  ctxPtr <- startMobileApp MobileApp
    { maContext     = loggingMobileContext
    , maView        = \_userState -> filesDirDemoView
    , maActionState = actionState
    }
  platformLog "FilesDir demo app registered"

  -- Now that the bridge is initialised, query the files directory.
  filesDir <- getAppFilesDir
  platformLog ("FilesDir: " <> pack filesDir)

  -- Write-read test (wrapped in try so a failure doesn't crash the app)
  let testFile = filesDir </> "hatter_filesdir_test.txt"
      testContent = "hatter-test-ok"
  writeResult <- try (writeFile testFile testContent) :: IO (Either SomeException ())
  case writeResult of
    Left err -> platformLog ("FilesDir write error: " <> pack (show err))
    Right () -> do
      readResult <- try (readFile testFile) :: IO (Either SomeException String)
      case readResult of
        Left err -> platformLog ("FilesDir read error: " <> pack (show err))
        Right content
          | content == testContent -> platformLog "FilesDir write-read OK"
          | otherwise -> platformLog ("FilesDir write-read FAIL: got " <> pack content)

  pure ctxPtr

-- | Displays the app files directory path.
filesDirDemoView :: IO Widget
filesDirDemoView = do
  filesDir <- getAppFilesDir
  pure $ Column
    [ Text TextConfig { tcLabel = "FilesDir Demo", tcFontConfig = Nothing }
    , Text TextConfig { tcLabel = pack filesDir, tcFontConfig = Nothing }
    ]
