-- | Default implementation of the @HaskellMobile.App@ Backpack signature.
-- Provides 'loggingMobileContext' as the application context, which logs
-- every lifecycle event via 'platformLog'.
module HaskellMobile.App (appContext) where

import HaskellMobile.Lifecycle (MobileContext, loggingMobileContext)

-- | The default application context — logs every lifecycle event.
appContext :: MobileContext
appContext = loggingMobileContext
