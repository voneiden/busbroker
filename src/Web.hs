{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

-- User.hs
module Web (runScotty) where

--import qualified Db
--import User (CreateUserRequest (..))

import Control.Concurrent.STM (atomically, flushTBQueue, newTBQueue, readTBQueue, writeTBQueue)
import Control.Monad.IO.Class
import Data.Aeson (FromJSON, ToJSON)
import Data.ByteString.Base64 (decodeLenient)
import qualified Data.ByteString.UTF8 as BSU
import Data.Coerce (coerce)
import Data.IORef (newIORef, readIORef, writeIORef)
import Data.List as List
import Data.List.Split (splitOn)
import Data.Maybe (fromMaybe, mapMaybe)
import qualified Data.Text as Text
import Data.Text.Encoding (encodeUtf8)
import GHC.Generics
import MessageData (MessageData (MessageData))
import qualified MessageData
import Network.HTTP.Types (noContent204)
import Network.Socket (SockAddr (SockAddrUnix))
import Network.Wai.Middleware.Cors (cors, corsRequestHeaders, simpleCors, simpleCorsResourcePolicy)
import RouterTypes
import Text.Read (readMaybe)
import Util (epoch)
import Web.Scotty (ActionM, get, json, jsonData, middleware, param, post, raise, scotty, status)
import Web.Scotty.Internal.Types (Middleware)

data PublishMessageRequest = PublishMessageRequest
  { pubTopic :: String,
    pubMessage :: String -- base64 encoded!
  }
  deriving (Generic)

instance FromJSON PublishMessageRequest

instance ToJSON PublishMessageRequest

data ConnectionStats = ConnectionStats
  { sockAddr :: String,
    ping :: Integer,
    created :: Integer,
    messagesIn :: Integer,
    messagesOut :: Integer
  }
  deriving (Show, Generic)

newtype ResponseData = ResponseData {connectionStats :: [ConnectionStats]}
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
  ConnectionStats (show $ RouterTypes.sockAddr stats) (RouterTypes.ping stats) (RouterTypes.created stats) (RouterTypes.messagesIn stats) (RouterTypes.messagesOut stats)

convertMessage :: Response -> Maybe MessageData
convertMessage response =
  case response of
    PubResponse (Topic topic') (Message message') (Timestamp timestamp) ->
      Just
        MessageData
          { MessageData.topic = topic',
            MessageData.message = BSU.toString message',
            MessageData.timestamp = timestamp
          }
    _ -> Nothing

getSockAddr :: SockAddr
getSockAddr = SockAddrUnix "REST"

corsWithContentType = cors (const $ Just policy)
  where
    policy =
      simpleCorsResourcePolicy
        { corsRequestHeaders = ["Content-Type"]
        }

runScotty :: RequestQueue -> IO ()
runScotty requestQueue = do
  statsResponseQueue <- atomically $ newTBQueue 1
  pubResponseQueue <- atomically $ newTBQueue 1000

  -- Run the scotty web app on port 8080
  scotty 18080 $ do
    -- Listen for POST requests on the "/users" endpoint
    middleware corsWithContentType
    get "/stats" $
      do
        _ <- liftIO $ atomically $ writeTBQueue (coerce requestQueue) (StatsRequest (ResponseQueue statsResponseQueue))
        stats <- liftIO $ atomically $ readTBQueue statsResponseQueue

        case stats of
          StatsResponse stats' ->
            json $
              ResponseData
                { connectionStats = List.map convertStats (coerce stats')
                }
          _ ->
            raise "Oh crap"
    --middleware simpleCors
    post "/cmd" $ do
      msg <- jsonData :: ActionM PublishMessageRequest
      let pubTopic' = splitOn "/" $ pubTopic msg
      let pubMessage' = decodeLenient $ BSU.fromString $ pubMessage msg

      _ <- liftIO $ atomically $ writeTBQueue (coerce requestQueue) (PubRequest getSockAddr (Topic pubTopic') (Message pubMessage'))
      status noContent204
