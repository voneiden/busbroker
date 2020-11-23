{-# LANGUAGE MultiParamTypeClasses #-}

module Queues.AlterRoute where

import Control.Concurrent.STM.TBQueue (TBQueue, readTBQueue, writeTBQueue)
import Queues.Publish (DeliveryQueue)
import Queues.Queue

data AlterRouteMessage
  = AddRouteMessage
      { topic :: String,
        queue :: DeliveryQueue
      }
  | DropRouteMessage
      { queue :: DeliveryQueue
      }
  | Publish
      { topic :: String,
        message :: String
      }

newtype AlterRouteQueue = AlterRouteQueue (TBQueue AlterRouteMessage)

instance Queue AlterRouteQueue AlterRouteMessage where
  recv (AlterRouteQueue q) = readTBQueue q
  send (AlterRouteQueue q) = writeTBQueue q
