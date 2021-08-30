module RouterTypes where

import Control.Concurrent.STM (TBQueue)
import Data.Map.Strict (Map)
import Data.ByteString (ByteString)

newtype Message = Message ByteString

newtype Topic = Topic String deriving (Eq, Ord)

data Request = SubRequest Topic ResponseQueue
             | UnsubRequest Topic ResponseQueue
             | PubRequest Topic Message
             | UnsubAllRequest ResponseQueue

data Response = PubResponse Topic Message

newtype RequestQueue = RequestQueue (TBQueue Request)

newtype ResponseQueue = ResponseQueue (TBQueue Response) deriving (Eq)

newtype RouteMap = RouteMap (Map Topic [ResponseQueue])
