{-# LANGUAGE ForeignFunctionInterface #-}
module HaskellMobile.FilesDir
  ( getAppFilesDir
  ) where

import Foreign.C.String (CString, peekCString)

foreign import ccall "getAppFilesDir" c_getAppFilesDir :: IO CString

-- | Returns the platform-specific app files directory path.
--
-- On Android this is the result of @getFilesDir().getAbsolutePath()@,
-- on iOS it is the Application Support directory, and on desktop it
-- falls back to @"."@ (the current working directory).
getAppFilesDir :: IO FilePath
getAppFilesDir = peekCString =<< c_getAppFilesDir
