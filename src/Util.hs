module Util (epoch) where

import Control.Concurrent.STM (STM, TBQueue, isFullTBQueue, readTBQueue, writeTBQueue)
import Data.Time.Clock.POSIX (getPOSIXTime)

epoch :: IO Integer
epoch = round . (* 1000) <$> getPOSIXTime

popAndWriteTBQueue :: TBQueue a -> a -> STM ()
popAndWriteTBQueue queue message = do
  full <- isFullTBQueue queue
  if full
    then do
      _ <- readTBQueue queue
      writeTBQueue queue message
    else writeTBQueue queue message
