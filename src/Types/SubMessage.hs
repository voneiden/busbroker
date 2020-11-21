module Types.SubMessage where

import Control.Concurrent.STM.TBQueue (TBQueue)
import Types.RouteMessage (RouteMessage)

data SubMessage = SubMessage
  { topic :: String
  , queue :: TBQueue RouteMessage
  } | UnsubMessage 
  { queue :: TBQueue RouteMessage 
  }
