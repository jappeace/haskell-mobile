{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE OverloadedStrings #-}
module HaskellMobile.Locale
  ( Language(..)
  , Locale(..)
  , LocaleFailure(..)
  , getSystemLocale
  , parseLocale
  , localeToText
  , languageToCode
  , languageFromCode
  , haskellLogLocale
  ) where

import Data.Char (isAlpha, isDigit, toUpper)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Foreign.C.String (CString, peekCString)
import HaskellMobile.Lifecycle (platformLog)

-- | ISO 639-1 language codes as a sum type.
data Language
  = Af -- ^ Afrikaans
  | Am -- ^ Amharic
  | Ar -- ^ Arabic
  | Az -- ^ Azerbaijani
  | Be -- ^ Belarusian
  | Bg -- ^ Bulgarian
  | Bn -- ^ Bengali
  | Bs -- ^ Bosnian
  | Ca -- ^ Catalan
  | Cs -- ^ Czech
  | Cy -- ^ Welsh
  | Da -- ^ Danish
  | De -- ^ German
  | El -- ^ Greek
  | En -- ^ English
  | Es -- ^ Spanish
  | Et -- ^ Estonian
  | Eu -- ^ Basque
  | Fa -- ^ Persian
  | Fi -- ^ Finnish
  | Fr -- ^ French
  | Ga -- ^ Irish
  | Gl -- ^ Galician
  | Gu -- ^ Gujarati
  | He -- ^ Hebrew
  | Hi -- ^ Hindi
  | Hr -- ^ Croatian
  | Hu -- ^ Hungarian
  | Hy -- ^ Armenian
  | Id -- ^ Indonesian
  | Is -- ^ Icelandic
  | It -- ^ Italian
  | Ja -- ^ Japanese
  | Ka -- ^ Georgian
  | Kk -- ^ Kazakh
  | Km -- ^ Khmer
  | Kn -- ^ Kannada
  | Ko -- ^ Korean
  | Lt -- ^ Lithuanian
  | Lv -- ^ Latvian
  | Mk -- ^ Macedonian
  | Ml -- ^ Malayalam
  | Mn -- ^ Mongolian
  | Mr -- ^ Marathi
  | Ms -- ^ Malay
  | My -- ^ Burmese
  | Nb -- ^ Norwegian Bokmal
  | Ne -- ^ Nepali
  | Nl -- ^ Dutch
  | No -- ^ Norwegian
  | Pa -- ^ Punjabi
  | Pl -- ^ Polish
  | Pt -- ^ Portuguese
  | Ro -- ^ Romanian
  | Ru -- ^ Russian
  | Si -- ^ Sinhala
  | Sk -- ^ Slovak
  | Sl -- ^ Slovenian
  | Sq -- ^ Albanian
  | Sr -- ^ Serbian
  | Sv -- ^ Swedish
  | Sw -- ^ Swahili
  | Ta -- ^ Tamil
  | Te -- ^ Telugu
  | Th -- ^ Thai
  | Tl -- ^ Filipino
  | Tr -- ^ Turkish
  | Uk -- ^ Ukrainian
  | Ur -- ^ Urdu
  | Uz -- ^ Uzbek
  | Vi -- ^ Vietnamese
  | Zh -- ^ Chinese
  | Zu -- ^ Zulu
  deriving (Show, Eq, Ord, Bounded, Enum)

-- | A parsed BCP-47 locale tag with language and optional region.
data Locale = Locale
  { locLanguage :: Language    -- ^ ISO 639-1 language code
  , locRegion   :: Maybe Text  -- ^ ISO 3166-1 region code: @\"US\"@, @\"NL\"@, @\"CN\"@
  } deriving (Show, Eq, Ord)

-- | Reasons a locale tag may fail to parse.
data LocaleFailure
  = EmptyLocaleTag
  | InvalidLanguageCode Text
  | InvalidRegionCode Text
  | MalformedLocaleTag Text
  deriving (Show, Eq)

foreign import ccall "getSystemLocale" c_getSystemLocale :: IO CString

-- | Query the system locale from the host platform.
--
-- * Android: @Locale.getDefault().toLanguageTag()@ (cached at JNI_OnLoad)
-- * iOS: @NSLocale.currentLocale@ (queried at bridge setup)
-- * Desktop: @LANG@ environment variable, defaults to @\"en\"@
getSystemLocale :: IO Text
getSystemLocale = do
  cstr <- c_getSystemLocale
  Text.pack <$> peekCString cstr

-- | Render a 'Language' to its ISO 639-1 code.
languageToCode :: Language -> Text
languageToCode Af = "af"
languageToCode Am = "am"
languageToCode Ar = "ar"
languageToCode Az = "az"
languageToCode Be = "be"
languageToCode Bg = "bg"
languageToCode Bn = "bn"
languageToCode Bs = "bs"
languageToCode Ca = "ca"
languageToCode Cs = "cs"
languageToCode Cy = "cy"
languageToCode Da = "da"
languageToCode De = "de"
languageToCode El = "el"
languageToCode En = "en"
languageToCode Es = "es"
languageToCode Et = "et"
languageToCode Eu = "eu"
languageToCode Fa = "fa"
languageToCode Fi = "fi"
languageToCode Fr = "fr"
languageToCode Ga = "ga"
languageToCode Gl = "gl"
languageToCode Gu = "gu"
languageToCode He = "he"
languageToCode Hi = "hi"
languageToCode Hr = "hr"
languageToCode Hu = "hu"
languageToCode Hy = "hy"
languageToCode Id = "id"
languageToCode Is = "is"
languageToCode It = "it"
languageToCode Ja = "ja"
languageToCode Ka = "ka"
languageToCode Kk = "kk"
languageToCode Km = "km"
languageToCode Kn = "kn"
languageToCode Ko = "ko"
languageToCode Lt = "lt"
languageToCode Lv = "lv"
languageToCode Mk = "mk"
languageToCode Ml = "ml"
languageToCode Mn = "mn"
languageToCode Mr = "mr"
languageToCode Ms = "ms"
languageToCode My = "my"
languageToCode Nb = "nb"
languageToCode Ne = "ne"
languageToCode Nl = "nl"
languageToCode No = "no"
languageToCode Pa = "pa"
languageToCode Pl = "pl"
languageToCode Pt = "pt"
languageToCode Ro = "ro"
languageToCode Ru = "ru"
languageToCode Si = "si"
languageToCode Sk = "sk"
languageToCode Sl = "sl"
languageToCode Sq = "sq"
languageToCode Sr = "sr"
languageToCode Sv = "sv"
languageToCode Sw = "sw"
languageToCode Ta = "ta"
languageToCode Te = "te"
languageToCode Th = "th"
languageToCode Tl = "tl"
languageToCode Tr = "tr"
languageToCode Uk = "uk"
languageToCode Ur = "ur"
languageToCode Uz = "uz"
languageToCode Vi = "vi"
languageToCode Zh = "zh"
languageToCode Zu = "zu"

-- | Parse a lowercase ISO 639-1 code into a 'Language'.
languageFromCode :: Text -> Maybe Language
languageFromCode code = Map.lookup (Text.toLower code) codeToLanguageMap

-- | Lookup table built once from the complete 'Language' enumeration.
codeToLanguageMap :: Map Text Language
codeToLanguageMap =
  Map.fromList [(languageToCode lang, lang) | lang <- [minBound .. maxBound]]

-- | Parse a BCP-47 locale tag like @\"en\"@, @\"en-US\"@, @\"nl-NL\"@.
--
-- Splits on @\'-\'@ or @\'_\'@, validates language (2-letter ISO 639-1)
-- and optional region (2 uppercase alpha or 3 digits).
-- Language is looked up in the 'Language' enum, region is normalised to uppercase.
parseLocale :: Text -> Either LocaleFailure Locale
parseLocale tag
  | Text.null tag = Left EmptyLocaleTag
  | otherwise =
      case splitLocaleTag tag of
        [rawLang] ->
          case languageFromCode rawLang of
            Nothing   -> Left (InvalidLanguageCode rawLang)
            Just lang -> Right (Locale lang Nothing)
        [rawLang, rawRegion] ->
          case languageFromCode rawLang of
            Nothing   -> Left (InvalidLanguageCode rawLang)
            Just lang ->
              case validateRegion rawRegion of
                Left failure -> Left failure
                Right region -> Right (Locale lang (Just region))
        _ -> Left (MalformedLocaleTag tag)

-- | Render a 'Locale' back to its BCP-47 text form.
localeToText :: Locale -> Text
localeToText (Locale lang Nothing)       = languageToCode lang
localeToText (Locale lang (Just region)) = languageToCode lang <> "-" <> region

-- | Log the detected system locale. Called from platform bridges during init.
haskellLogLocale :: IO ()
haskellLogLocale = do
  raw <- getSystemLocale
  platformLog ("Locale raw: " <> raw)
  case parseLocale raw of
    Right locale  -> platformLog ("Locale parsed: " <> localeToText locale)
    Left failure  -> platformLog ("Locale parse failed: " <> Text.pack (show failure))

foreign export ccall haskellLogLocale :: IO ()

-- Internal helpers

-- | Split a locale tag on @\'-\'@ or @\'_\'@ into at most 2 parts
-- (language and optional region). Extra segments are dropped to keep
-- the result simple — we only care about language + region.
splitLocaleTag :: Text -> [Text]
splitLocaleTag input =
  let parts = Text.split (\c -> c == '-' || c == '_') input
  in  take 2 (filter (not . Text.null) parts)

-- | Validate and normalise a region code.
-- Accepts 2 alpha characters (normalised to uppercase) or 3 digits.
validateRegion :: Text -> Either LocaleFailure Text
validateRegion raw
  | Text.length raw == 2 && Text.all isAlpha raw =
      Right (Text.map toUpper raw)
  | Text.length raw == 3 && Text.all isDigit raw =
      Right raw
  | otherwise = Left (InvalidRegionCode raw)
