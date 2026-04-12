{-# LANGUAGE OverloadedStrings #-}
-- | Mobile entry point for the files-dir-demo test app.
--
-- Used by the emulator and simulator files directory integration tests.
-- On startup, retrieves the app files directory, writes a test file,
-- reads it back, and logs the result.
module Main where

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
  filesDir <- getAppFilesDir
  platformLog ("FilesDir: " <> pack filesDir)

  -- Write-read test
  let testFile = filesDir </> "hatter_filesdir_test.txt"
      testContent = "hatter-test-ok"
  writeFile testFile testContent
  result <- readFile testFile
  if result == testContent
    then platformLog "FilesDir write-read OK"
    else platformLog ("FilesDir write-read FAIL: got " <> pack result)

  ctxPtr <- startMobileApp MobileApp
    { maContext     = loggingMobileContext
    , maView        = \_userState -> filesDirDemoView filesDir
    , maActionState = actionState
    }
  platformLog "FilesDir demo app registered"
  pure ctxPtr

-- | Displays the app files directory path.
filesDirDemoView :: FilePath -> IO Widget
filesDirDemoView filesDir = pure $ Column
  [ Text TextConfig { tcLabel = "FilesDir Demo", tcFontConfig = Nothing }
  , Text TextConfig { tcLabel = pack filesDir, tcFontConfig = Nothing }
  ]
