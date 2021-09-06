{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

-- User.hs
module Web (runScotty) where

--import qualified Db
--import User (CreateUserRequest (..))

import Control.Concurrent.STM (atomically, flushTBQueue, newTBQueue, readTBQueue, writeTBQueue)
import Control.Monad.IO.Class
import Data.Aeson (FromJSON, ToJSON)
import qualified Data.ByteString.UTF8 as BSU
import Data.Coerce (coerce)
import Data.List as List
import Data.Text
import GHC.Generics
import Network.Socket (SockAddr (SockAddrUnix))
import RouterTypes
import Web.Scotty (ActionM, get, json, jsonData, post, raise, scotty, middleware)
import Data.Maybe (mapMaybe)
import Network.Wai.Middleware.Cors (simpleCors)

data User = User
  { userId :: Text,
    userName :: Text
  }

-- Data type which describes the request which
-- will be received to create a user
data CreateUserRequest = CreateUserRequest
  { name :: Text,
    password :: Text
  }
  deriving (Generic)

-- We define a FromJSON instance for CreateUserRequest
-- because we will want to parse it from a HTTP request
-- body (JSON).
instance FromJSON CreateUserRequest

instance ToJSON CreateUserRequest

data ConnectionStats = ConnectionStats
  { sockAddr :: String,
    ping :: Integer,
    created :: Integer,
    messagesIn :: Integer,
    messagesOut :: Integer
  }
  deriving (Show, Generic)

data MessageData = MessageData
  { topic :: [String],
    message :: String
  }
  deriving (Show, Generic)

data ResponseData = ResponseData
  { connectionStats :: [ConnectionStats],
    messages :: [MessageData]
  }
  deriving (Show, Generic)

--data StatsWrapper = StatsWrapper { stats :: [Stats]}

instance FromJSON ConnectionStats

instance ToJSON ConnectionStats

instance FromJSON MessageData

instance ToJSON MessageData

instance FromJSON ResponseData

instance ToJSON ResponseData

convertStats :: QueueStatistics -> ConnectionStats
convertStats stats =
  ConnectionStats (show $ queueSockAddr stats) (queuePing stats) (queueCreated stats) (queueMessagesIn stats) (queueMessagesOut stats)

convertMessage :: Response -> Maybe MessageData
convertMessage response =
  case response of
    PubResponse (Topic topic') (Message message') ->
      Just
        MessageData
          { topic = topic',
            message = BSU.toString message'
          }

    _ -> Nothing
getSockAddr :: SockAddr
getSockAddr = SockAddrUnix "REST"

runScotty :: RequestQueue -> IO ()
runScotty requestQueue = do
  statsResponseQueue <- atomically $ newTBQueue 1
  pubResponseQueue <- atomically $ newTBQueue 1000
  -- Subscribe to everything
  _ <- atomically $ writeTBQueue (coerce requestQueue) (SubRequest (Topic ["#"]) (ResponseQueue pubResponseQueue, getSockAddr))

  -- Run the scotty web app on port 8080
  scotty 18080 $ do
    -- Listen for POST requests on the "/users" endpoint
    middleware simpleCors
    get "/stats" $
      do
        _ <- liftIO $ atomically $ writeTBQueue (coerce requestQueue) (StatsRequest (ResponseQueue statsResponseQueue))
        stats <- liftIO $ atomically $ readTBQueue statsResponseQueue
        messages' <- liftIO $ atomically $ flushTBQueue pubResponseQueue
        case stats of
          StatsResponse stats' ->
            json $
              ResponseData
                { connectionStats = List.map convertStats (coerce stats')
                , messages = mapMaybe convertMessage messages'
                }
          _ ->
            raise "Oh crap"
