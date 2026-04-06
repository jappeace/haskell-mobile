{-# LANGUAGE OverloadedStrings #-}
module HaskellMobile.I18n
  ( Key(..)
  , translate
  ) where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import HaskellMobile.Locale (Locale(..))

-- | Translation key. Newtype for type safety.
newtype Key = Key { unKey :: Text }
  deriving (Show, Eq, Ord)

-- | Look up a translation key with fallback chain:
--
--   1. Exact locale match (e.g., @\"nl-NL\"@)
--   2. Language-only match (e.g., @\"nl\"@)
--   3. 'Nothing'
translate :: Map Locale (Map Key Text) -> Locale -> Key -> Maybe Text
translate translations locale key =
  case lookupKey translations locale key of
    Just foundText -> Just foundText
    Nothing        -> lookupKey translations (locale { locRegion = Nothing }) key

-- Internal helpers

lookupKey :: Map Locale (Map Key Text) -> Locale -> Key -> Maybe Text
lookupKey translations locale key =
  Map.lookup locale translations >>= Map.lookup key
