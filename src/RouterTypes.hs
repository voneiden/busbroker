module RouterTypes where

import Control.Concurrent.STM (TBQueue)
import Data.ByteString (ByteString)
import Data.Map.Strict (Map)
import Network.Socket (SockAddr)

newtype Message = Message ByteString

-- TODO use Topic [String] rather so that it is already split so we don't have to split when matching
newtype Topic = Topic [String] deriving (Eq, Ord, Show)

-- Requests are processed by Router
data Request
  = SubRequest Topic ResponseQueue
  | UnsubRequest Topic ResponseQueue
  | PubRequest SockAddr Topic Message
  | UnsubAllRequest ResponseQueue
  | IdentifyRequest SockAddr String
  | PongRequest SockAddr Integer

-- Responses are processed by those who request
data Response = PubResponse Topic Message | Ping Integer

newtype RequestQueue = RequestQueue (TBQueue Request)

newtype ResponseQueue = ResponseQueue (TBQueue Response) deriving (Eq)

newtype RouteMap = RouteMap (Map Topic [ResponseQueue])

data QueueStatistics = QueueStatistics
  { queueName :: String,
    queuePing :: Integer,
    queueCreated :: Integer,
    queueMessagesIn :: Integer,
    queueMessagesOut :: Integer
  }
  deriving (Show)

newtype QueueStatisticsMap = QueueStatisticsMap (Map SockAddr QueueStatistics) deriving (Show)
