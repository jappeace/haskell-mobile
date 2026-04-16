{-# LANGUAGE OverloadedStrings #-}
-- | Mobile entry point for the platform-sign-in-demo test app.
--
-- Used by the emulator and simulator platform sign-in integration tests.
-- Starts directly in platform-sign-in-demo mode so no runtime switching
-- is needed.
module Main where

import Data.IORef (newIORef, readIORef, writeIORef)
import Foreign.Ptr (Ptr)
import Hatter
  ( MobileApp(..)
  , Action
  , startMobileApp
  , platformLog
  , loggingMobileContext
  , newActionState
  , runActionM
  , createAction
  )
import Hatter.AppContext (AppContext(..), derefAppContext)
import Hatter.PlatformSignIn
  ( SignInProvider(..)
  , SignInResult(..)
  , SignInCredential(..)
  , PlatformSignInState(..)
  , startPlatformSignIn
  )
import Hatter.Widget
  ( ButtonConfig(..)
  , TextConfig(..)
  , Widget(..)
  , column
  )

main :: IO (Ptr AppContext)
main = do
  platformLog "PlatformSignIn demo app registered"
  actionState <- newActionState
  signInStateRef <- newIORef (Nothing :: Maybe PlatformSignInState)
  onAppleSignIn <- runActionM actionState $
    createAction $ do
      Just signInState <- readIORef signInStateRef
      startPlatformSignIn signInState AppleSignIn
        (\result -> case result of
          SignInSuccess credential ->
            platformLog ("PlatformSignIn Apple success: " <> sicUserId credential)
          SignInCancelled ->
            platformLog "PlatformSignIn Apple cancelled"
          SignInError errorMsg ->
            platformLog ("PlatformSignIn Apple error: " <> errorMsg)
        )
  onGoogleSignIn <- runActionM actionState $
    createAction $ do
      Just signInState <- readIORef signInStateRef
      startPlatformSignIn signInState GoogleSignIn
        (\result -> case result of
          SignInSuccess credential ->
            platformLog ("PlatformSignIn Google success: " <> sicUserId credential)
          SignInCancelled ->
            platformLog "PlatformSignIn Google cancelled"
          SignInError errorMsg ->
            platformLog ("PlatformSignIn Google error: " <> errorMsg)
        )
  ctxPtr <- startMobileApp MobileApp
    { maContext     = loggingMobileContext
    , maView        = \_userState -> platformSignInDemoView onAppleSignIn onGoogleSignIn
    , maActionState = actionState
    }
  appCtx <- derefAppContext ctxPtr
  writeIORef signInStateRef (Just (acPlatformSignInState appCtx))
  pure ctxPtr

-- | Builds a Column with a label and two sign-in buttons.
platformSignInDemoView :: Action -> Action -> IO Widget
platformSignInDemoView onAppleSignIn onGoogleSignIn = pure $ column
  [ Text TextConfig { tcLabel = "PlatformSignIn Demo", tcFontConfig = Nothing }
  , Button ButtonConfig
      { bcLabel      = "Sign in with Apple"
      , bcAction     = onAppleSignIn
      , bcFontConfig = Nothing
      }
  , Button ButtonConfig
      { bcLabel      = "Sign in with Google"
      , bcAction     = onGoogleSignIn
      , bcFontConfig = Nothing
      }
  ]
