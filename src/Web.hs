{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
-- User.hs
module Web (runScotty) where

import Data.Aeson (FromJSON, ToJSON)
import GHC.Generics
import Control.Monad.IO.Class
import Data.Text
--import qualified Db
--import User (CreateUserRequest (..))
import Web.Scotty (json, scotty, post, jsonData, ActionM, get, raise)
import RouterTypes
import Control.Concurrent.STM (atomically, newTBQueue, writeTBQueue, readTBQueue)
import Data.Coerce (coerce)
import Data.List as List

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


data Stats = Stats
  { sockAddr :: String,
    ping :: Integer,
    created :: Integer,
    messagesIn :: Integer,
    messagesOut :: Integer
  }
  deriving (Show, Generic)

--data StatsWrapper = StatsWrapper { stats :: [Stats]}

instance FromJSON Stats
instance ToJSON Stats

convertStats :: QueueStatistics -> Stats
convertStats stats =
  Stats (show $ queueSockAddr stats) (queuePing stats) (queueCreated stats) (queueMessagesIn stats) (queueMessagesOut stats)

runScotty :: RequestQueue -> IO ()
runScotty statsRequestQueue = do
  -- Run the scotty web app on port 8080
  statsResponseQueue <- atomically $ newTBQueue 1000
  scotty 18080 $ do
    -- Listen for POST requests on the "/users" endpoint
    get "/stats" $
      do
        _ <- liftIO $ atomically $ writeTBQueue (coerce statsRequestQueue) (StatsRequest (ResponseQueue statsResponseQueue))
        stats <- liftIO $ atomically $ readTBQueue statsResponseQueue
        case stats of 
          StatsResponse stats' -> 
            json $ List.map convertStats (coerce stats')
          _ -> 
            raise "Oh crap"
        -- parse the request body into our CreateUserRequest type
        --createUserReq <- jsonData :: ActionM CreateUserRequest
        --let x = [Stats "test" 1 2 3 4]
        --json x
        -- Create our new user.
        -- In order for this compile we need to use liftIO here to lift the IO from our
        -- createUser function. This is because the `post` function from scotty expects an
        -- ActionM action instead of an IO action
        --newUserId <- liftIO $ createUser createUserReq

        -- Return the user ID of the new user in the HTTP response
        --
