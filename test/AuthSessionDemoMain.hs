{-# LANGUAGE OverloadedStrings #-}
-- | Mobile entry point for the auth-session-demo test app.
--
-- Used by the emulator and simulator auth session integration tests.
-- Starts directly in auth-session-demo mode so no runtime switching is needed.
module Main where

import Data.Text (pack)
import Foreign.Ptr (Ptr)
import HaskellMobile
  ( MobileApp(..)
  , UserState(..)
  , startMobileApp
  , platformLog
  , loggingMobileContext
  , AppContext
  , AuthSessionResult(..)
  , startAuthSession
  )
import HaskellMobile.Widget
  ( ButtonConfig(..)
  , TextConfig(..)
  , Widget(..)
  )

main :: IO (Ptr AppContext)
main = do
  platformLog "AuthSession demo app registered"
  startMobileApp authSessionDemoApp

-- | AuthSession demo: button starts an auth session, logs the result.
authSessionDemoApp :: MobileApp
authSessionDemoApp = MobileApp
  { maContext = loggingMobileContext
  , maView    = authSessionDemoView
  }

-- | Builds a Column with a label and a "Start Login" button.
-- The button starts an auth session with a demo URL.
authSessionDemoView :: UserState -> IO Widget
authSessionDemoView userState = do
  pure $ Column
    [ Text TextConfig { tcLabel = "AuthSession Demo", tcFontConfig = Nothing }
    , Button ButtonConfig
        { bcLabel = "Start Login"
        , bcAction = startAuthSession
            (userAuthSessionState userState)
            "https://example.com/auth?client_id=demo&redirect_uri=haskellmobile://callback"
            "haskellmobile"
            (\result -> case result of
              AuthSessionSuccess redirectUrl ->
                platformLog ("AuthSession success: " <> redirectUrl)
              AuthSessionCancelled ->
                platformLog "AuthSession cancelled"
              AuthSessionError errorMsg ->
                platformLog ("AuthSession error: " <> errorMsg)
            )
        , bcFontConfig = Nothing
        }
    ]
