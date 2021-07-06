{-# LANGUAGE MultiParamTypeClasses #-}

module AlterRoute where

import Publish (PublishQueue)
import Queue (Queue, recv, send)
import Control.Concurrent.STM.TBQueue (TBQueue, readTBQueue, writeTBQueue)
import Data.Coerce (coerce)

data AlterRoute
  = AddRoute
      { topic :: String,
        queue :: PublishQueue
      }
  | DropRoute
      { queue :: PublishQueue
      }

newtype AlterRouteQueue = AlterRouteQueue (TBQueue AlterRoute)

instance Queue AlterRouteQueue AlterRoute where
  recv = readTBQueue . coerce
  send = writeTBQueue . coerce
