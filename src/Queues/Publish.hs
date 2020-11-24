{-# LANGUAGE MultiParamTypeClasses #-}

module Queues.Publish where

import Control.Concurrent.STM.TBQueue (TBQueue, readTBQueue, writeTBQueue)
import Queues.Queue
import Data.Coerce (coerce)

data Publish = Publish
  { topic :: String,
    message :: String
  }


newtype PublishQueue = PublishQueue (TBQueue Publish) deriving Eq

instance Queue PublishQueue Publish where
  recv = readTBQueue . coerce
  send = writeTBQueue . coerce
