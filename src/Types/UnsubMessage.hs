module Types.UnsubMessage where

import Control.Concurrent.STM.TBQueue (TBQueue)
import Types.RouteMessage (RouteMessage)

data UnsubMessage = UnsubMessage
  { queue :: TBQueue RouteMessage
  }
