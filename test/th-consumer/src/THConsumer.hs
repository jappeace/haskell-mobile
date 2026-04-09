{-# LANGUAGE TemplateHaskell #-}
-- | Minimal module that forces a Template Haskell splice at compile time.
-- If this compiles during aarch64-android cross-compilation, TH works.
module THConsumer (thGreeting) where

import Language.Haskell.TH.Syntax (lift)

-- | Compile-time evaluated splice — forces iserv-proxy TH evaluation.
thGreeting :: String
thGreeting = $(lift ("Hello from Template Haskell" :: String))
