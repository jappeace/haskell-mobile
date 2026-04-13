{-# LANGUAGE OverloadedStrings #-}
-- | Mobile entry point for the auth-session-demo test app.
--
-- Used by the emulator and simulator auth session integration tests.
-- Starts directly in auth-session-demo mode so no runtime switching is needed.
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
import Hatter.AuthSession (AuthSessionResult(..), AuthSessionState(..), startAuthSession)
import Hatter.Widget
  ( ButtonConfig(..)
  , TextConfig(..)
  , Widget(..)
  )

main :: IO (Ptr AppContext)
main = do
  platformLog "AuthSession demo app registered"
  actionState <- newActionState
  authStateRef <- newIORef (Nothing :: Maybe AuthSessionState)
  onStartLogin <- runActionM actionState $
    createAction $ do
      Just authState <- readIORef authStateRef
      startAuthSession authState
        "https://example.com/auth?client_id=demo&redirect_uri=hatter://callback"
        "hatter"
        (\result -> case result of
          AuthSessionSuccess redirectUrl ->
            platformLog ("AuthSession success: " <> redirectUrl)
          AuthSessionCancelled ->
            platformLog "AuthSession cancelled"
          AuthSessionError errorMsg ->
            platformLog ("AuthSession error: " <> errorMsg)
        )
  ctxPtr <- startMobileApp MobileApp
    { maContext     = loggingMobileContext
    , maView        = \_userState -> authSessionDemoView onStartLogin
    , maActionState = actionState
    }
  appCtx <- derefAppContext ctxPtr
  writeIORef authStateRef (Just (acAuthSessionState appCtx))
  pure ctxPtr

-- | Builds a Column with a label and a "Start Login" button.
authSessionDemoView :: Action -> IO Widget
authSessionDemoView onStartLogin = pure $ Column
  [ Text TextConfig { tcLabel = "AuthSession Demo", tcFontConfig = Nothing }
  , Button ButtonConfig
      { bcLabel      = "Start Login"
      , bcAction     = onStartLogin
      , bcFontConfig = Nothing
      }
  ]
