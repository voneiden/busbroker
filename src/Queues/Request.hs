{-# LANGUAGE MultiParamTypeClasses #-}

module Queues.Request where

import Control.Concurrent.STM.TBQueue (TBQueue, readTBQueue, writeTBQueue)
import Data.Coerce (coerce)
import Queues.Publish (PublishQueue)
import Queues.Queue

data Request
  = AddRouteRequest
      { topic :: String,
        queue :: PublishQueue
      }
  | DropRouteRequest
      { queue :: PublishQueue
      }
  | PublishRequest
      { topic :: String,
        message :: String
      }

newtype RequestQueue = RequestQueue (TBQueue Request)

instance Queue RequestQueue Request where
  recv = readTBQueue . coerce
  send = writeTBQueue . coerce
