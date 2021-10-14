{-# LANGUAGE DeriveGeneric #-}

module RouterTypes where

import Control.Concurrent.STM (TBQueue)
import Data.ByteString (ByteString)
import Data.Map.Strict (Map)
import Network.Socket (SockAddr)
import GHC.Generics (Generic)
import Data.Word (Word8)

newtype Message = Message ByteString deriving (Show)

-- TODO use Topic [String] rather so that it is already split so we don't have to split when matching
newtype Topic = Topic [String] deriving (Eq, Ord, Show)

newtype Timestamp = Timestamp Integer deriving (Show)

-- Requests are processed by Router
data Request
  = SubRequest Topic (ResponseQueue, SockAddr)
  | UnsubRequest Topic (ResponseQueue, SockAddr)
  | PubRequest SockAddr Topic Message
  | UnsubAllRequest (ResponseQueue, SockAddr)
  | IdentifyRequest SockAddr (Maybe ResponseQueue)
  | PingAllRequest
  | PongRequest SockAddr Integer
  | UnidentifyRequest SockAddr (Maybe ResponseQueue)
  | StatsRequest ResponseQueue

-- Responses are processed by those who request
data Response
  = PubResponse Topic Message Timestamp
  | PingResponse Integer
  | StatsResponse [QueueStatistics]
  | ReconfigureMacResponse Word8
  deriving (Show)

newtype RequestQueue = RequestQueue (TBQueue Request)

newtype ResponseQueue = ResponseQueue (TBQueue Response) deriving (Eq)

newtype RouteMap = RouteMap (Map Topic [(ResponseQueue, SockAddr)])

data QueueStatistics = QueueStatistics
  { sockAddr :: SockAddr,
    ping :: Integer,
    created :: Integer,
    messagesIn :: Integer,
    messagesOut :: Integer
  }
  deriving (Show, Generic)

newtype QueueStatisticsMap = QueueStatisticsMap (Map SockAddr QueueStatistics) deriving (Show)
newtype PingResponseQueues = PingResponseQueues [ResponseQueue]



