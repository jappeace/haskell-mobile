{-# LANGUAGE ForeignFunctionInterface #-}
-- | Unit tests for the app files directory bridge.
module Test.FilesDirTests
  ( filesDirTests
  ) where

import Test.Tasty
import Test.Tasty.HUnit

import Foreign.C.String (CString, newCString)
import System.Directory (removeFile, getTemporaryDirectory)
import System.FilePath ((</>))
import HaskellMobile.FilesDir (getAppFilesDir)

foreign import ccall "setAppFilesDir" c_setAppFilesDir :: CString -> IO ()

-- | Tests run sequentially (via 'sequentialTestGroup') because they
-- mutate a process-wide C global.
filesDirTests :: TestTree
filesDirTests = sequentialTestGroup "FilesDir" AllFinish
  [ testCase "getAppFilesDir returns non-empty path" $ do
      path <- getAppFilesDir
      assertBool "path should not be empty" (not (null path))
  , testCase "setAppFilesDir / getAppFilesDir roundtrip" $ do
      tmpDir <- getTemporaryDirectory
      cstr <- newCString tmpDir
      c_setAppFilesDir cstr
      path <- getAppFilesDir
      path @?= tmpDir
      -- Restore desktop default
      cstrDot <- newCString "."
      c_setAppFilesDir cstrDot
  , testCase "can write file to app files dir" $ do
      dir <- getAppFilesDir
      let testFile = dir </> "hatter_filesdir_test.txt"
          testContent = "hatter-test-ok"
      writeFile testFile testContent
      result <- readFile testFile
      result @?= testContent
      removeFile testFile
  ]
