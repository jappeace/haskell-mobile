{-# LANGUAGE OverloadedStrings #-}
module Hatter.I18n
  ( Key(..)
  , TranslateFailure(..)
  , translate
  ) where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Hatter.Locale (Locale(..))

-- | Translation key. Newtype for type safety.
newtype Key = Key { unKey :: Text }
  deriving (Show, Eq, Ord)

-- | Reasons a translation lookup can fail.
data TranslateFailure
  = LocaleNotFound Locale
    -- ^ The translations map has no entry for this locale.
  | KeyNotFound Locale Key
    -- ^ The locale exists but does not contain this key.
  deriving (Show, Eq)

-- | Look up a translation key with fallback chain:
--
--   1. Exact locale match (e.g., @\"nl-NL\"@)
--   2. Language-only match (e.g., @\"nl\"@)
--   3. Error describing which step failed
translate :: Map Locale (Map Key Text) -> Locale -> Key -> Either TranslateFailure Text
translate translations locale key =
  case lookupKey translations locale key of
    Right foundText -> Right foundText
    Left _exactFailure ->
      let fallbackLocale = locale { locRegion = Nothing }
      in  lookupKey translations fallbackLocale key

lookupKey :: Map Locale (Map Key Text) -> Locale -> Key -> Either TranslateFailure Text
lookupKey translations locale key =
  case Map.lookup locale translations of
    Nothing       -> Left (LocaleNotFound locale)
    Just keyMap ->
      case Map.lookup key keyMap of
        Nothing    -> Left (KeyNotFound locale key)
        Just value -> Right value
