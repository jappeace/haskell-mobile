{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
-- | Consumer simulation demo app — exercises the crossDeps + extraJniBridge
-- build path with a heavy Hackage dependency (aeson).
--
-- This reproduces the build configuration used by real consumer apps like
-- prrrrrrrrr, which crashed with SIGSEGV at startup (issue #156).
-- Hatter's own test APKs all use empty crossDeps; this test ensures the
-- consumer build path also produces a working .so under ARM binary translation.
--
-- aeson pulls in a large transitive dep tree (scientific, vector, attoparsec,
-- hashable, unordered-containers, primitive, etc.), producing a significantly
-- larger .so that is more likely to trigger libndk_translation bugs.
module Main where

import Data.Aeson (encode, ToJSON)
import Data.Text qualified as Text
import Data.ByteString.Lazy qualified as BSL
import Foreign.Ptr (Ptr)
import GHC.Generics (Generic)
import Hatter (MobileApp(..), startMobileApp, platformLog, loggingMobileContext, newActionState)
import Hatter.AppContext (AppContext)
import Hatter.Widget (Widget(..), TextConfig(..))

-- | Minimal type with ToJSON to force aeson's full code path.
data ConsumerPayload = ConsumerPayload
  { cpName  :: Text.Text
  , cpValue :: Int
  } deriving (Generic)

instance ToJSON ConsumerPayload

main :: IO (Ptr AppContext)
main = do
  platformLog "ConsumerSim demo app registered"
  let payload = ConsumerPayload { cpName = "test", cpValue = 42 }
      jsonBytes = encode payload
  platformLog ("aeson sanity: " <> Text.pack (show (BSL.length jsonBytes)) <> " bytes")
  actionState <- newActionState
  startMobileApp MobileApp
    { maContext     = loggingMobileContext
    , maView        = \_userState -> pure (Text TextConfig { tcLabel = "Consumer sim", tcFontConfig = Nothing })
    , maActionState = actionState
    }
