{-# LANGUAGE MultiParamTypeClasses #-}

module Publish where

import Control.Concurrent.STM.TBQueue (TBQueue, readTBQueue, writeTBQueue)
import Data.Coerce (coerce)
import Queue (Queue, recv, send)

data Publish = Publish
  { topic :: String,
    message :: String
  }

newtype RoutePublishQueue = RoutePublishQueue (TBQueue Publish)

newtype PublishQueue = PublishQueue (TBQueue Publish) deriving (Eq)

instance Queue RoutePublishQueue Publish where
  recv = readTBQueue . coerce
  send = writeTBQueue . coerce

instance Queue PublishQueue Publish where
  recv = readTBQueue . coerce
  send = writeTBQueue . coerce
