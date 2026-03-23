module Main where

import Test.Tasty
import Test.Tasty.QuickCheck as QC
import Test.Tasty.HUnit

import Data.List (sort)
import Data.IORef (newIORef, readIORef, modifyIORef')
import Foreign.C.String (newCString, peekCString)
import Foreign.Marshal.Alloc (free)
import Foreign.Ptr (Ptr)
import Foreign.StablePtr (castStablePtrToPtr)
import qualified HaskellMobile
import HaskellMobile (appContext)
import HaskellMobile.Lifecycle
  ( LifecycleEvent(..)
  , MobileContext(..)
  , lifecycleFromInt
  , lifecycleToInt
  , loggingMobileContext
  , newMobileContext
  , freeMobileContext
  , haskellOnLifecycle
  )

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "Tests" [qcProps, unitTests, lifecycleTests]

qcProps :: TestTree
qcProps = testGroup "(checked by QuickCheck)"
  [ QC.testProperty "sort == sort . reverse" $
      \list -> sort (list :: [Int]) == sort (reverse list)
  , QC.testProperty "Fermat's little theorem" $
      \x -> ((x :: Integer)^zeven  - x) `mod` zeven == 0
  ]
  where
    zeven :: Integer
    zeven = 7

oneTwoThree :: [Int]
oneTwoThree = [1, 2, 3]

unitTests :: TestTree
unitTests = testGroup "Unit tests"
  [ testCase "List comparison (different length)" $
       oneTwoThree `compare` [1,2] @?= GT

  -- the following test does not hold
  , testCase "List comparison (same length)" $
      oneTwoThree `compare` [1,2,3] @?= EQ
  , testCase "run main" $ do
      HaskellMobile.main
  , testCase "haskellGreet returns correct greeting" $ do
      cname <- newCString "World"
      cresult <- HaskellMobile.haskellGreet cname
      result <- peekCString cresult
      free cresult
      free cname
      result @?= "Hello from Haskell, World!"
  , testCase "haskellGreet with different input" $ do
      cname <- newCString "Android"
      cresult <- HaskellMobile.haskellGreet cname
      result <- peekCString cresult
      free cresult
      free cname
      result @?= "Hello from Haskell, Android!"
  ]

-- | Helper: create a context with the given callback, run an action with
-- the opaque 'Ptr ()', then free the context.
withContext :: (LifecycleEvent -> IO ()) -> (Ptr () -> IO a) -> IO a
withContext callback action = do
  sptr <- newMobileContext MobileContext { onLifecycle = callback }
  let ptr = castStablePtrToPtr sptr
  result <- action ptr
  freeMobileContext sptr
  pure result

allEvents :: [LifecycleEvent]
allEvents = [Create, Start, Resume, Pause, Stop, Destroy, LowMemory]

lifecycleTests :: TestTree
lifecycleTests = testGroup "Lifecycle"
  [ testCase "lifecycleToInt produces sequential codes 0-6" $
      map lifecycleToInt allEvents @?= [0, 1, 2, 3, 4, 5, 6]
  , testCase "lifecycleFromInt roundtrips for all events" $
      mapM_ (\event ->
        lifecycleFromInt (lifecycleToInt event) @?= Just event
      ) allEvents
  , testCase "lifecycleFromInt returns Nothing for unknown codes" $ do
      lifecycleFromInt 7 @?= Nothing
      lifecycleFromInt (-1) @?= Nothing
      lifecycleFromInt 100 @?= Nothing
  , testCase "callback receives dispatched event" $ do
      ref <- newIORef ([] :: [LifecycleEvent])
      withContext (\event -> modifyIORef' ref (++ [event])) $ \ctx ->
        haskellOnLifecycle ctx 2
      received <- readIORef ref
      received @?= [Resume]
  , testCase "unknown codes are silently ignored" $ do
      ref <- newIORef (0 :: Int)
      withContext (\_ -> modifyIORef' ref (+ 1)) $ \ctx -> do
        haskellOnLifecycle ctx 99
        haskellOnLifecycle ctx (-1)
      count <- readIORef ref
      count @?= 0
  , testCase "all 7 event types received in order" $ do
      ref <- newIORef ([] :: [LifecycleEvent])
      withContext (\event -> modifyIORef' ref (++ [event])) $ \ctx ->
        mapM_ (haskellOnLifecycle ctx . lifecycleToInt) allEvents
      received <- readIORef ref
      received @?= allEvents
  , testCase "loggingMobileContext handles all events without throwing" $
      mapM_ (onLifecycle loggingMobileContext) allEvents
  , testCase "appContext handles all events without throwing" $
      mapM_ (onLifecycle appContext) allEvents
  ]
