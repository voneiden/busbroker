{-# LANGUAGE OverloadedStrings #-}

module WebSocket where

import Control.Concurrent (MVar, forkIO, modifyMVar, modifyMVar_, newMVar, readMVar, killThread)
import Control.Concurrent.STM (atomically, flushTBQueue, newTBQueue, peekTBQueue, readTBQueue, writeTBQueue)
import Control.Exception (finally)
import Control.Monad (forM_, forever)
import Data.Aeson (FromJSON, ToJSON (..), decode, encode, object, (.=))
import Data.ByteString.Base64 (decodeLenient)
import qualified Data.ByteString.Base64 as B64
import qualified Data.ByteString.Lazy.UTF8 as LBSU
import qualified Data.ByteString.UTF8 as BSU
import Data.Char (isPunctuation, isSpace)
import Data.Coerce (coerce)
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import qualified Data.IP as IP
import Data.List as List
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.IO as Text
import Data.UUID (UUID)
import Data.UUID.V4 (nextRandom)
import GHC.Generics (Generic)
import MessageData
import Network.Socket (SockAddr (SockAddrInet, SockAddrInet6, SockAddrUnix))
import qualified Network.WebSockets as WS
import RouterTypes
import Util (epoch)

instance ToJSON MessageData

instance FromJSON MessageData

instance ToJSON QueueStatistics

--instance Generic SockAddr

instance ToJSON SockAddr where
  toJSON (SockAddrInet port addr) =
    let ip = IP.fromHostAddress addr
     in object
          [ "addr" .= show ip,
            "port" .= show port
          ]
  toJSON (SockAddrInet6 port _ addr _) =
    let ip = IP.fromHostAddress6 addr
     in object
          [ "addr" .= show ip,
            "port" .= show port
          ]
  toJSON (SockAddrUnix path) =
    object ["path" .= show path]

type Client = (UUID, WS.Connection)

type ServerState = [Client]

newServerState :: ServerState
newServerState = []

numClients :: ServerState -> Int
numClients = length

addClient :: Client -> ServerState -> ServerState
addClient client clients = client : clients

removeClient :: Client -> ServerState -> ServerState
removeClient client = filter ((/= fst client) . fst)

broadcast :: Text -> ServerState -> IO ()
broadcast message clients = do
  Text.putStrLn message
  forM_ clients $ \(_, conn) -> WS.sendTextData conn message

-- TODO disconnect doesn't unsub???
runWebsockets :: RequestQueue -> IO ()
runWebsockets requestQueue = do
  state <- newMVar newServerState
  messagesHistory <- newIORef ([] :: [MessageData])
  pubHistoryResponseQueue <- atomically $ newTBQueue 1000
  _ <- atomically $ writeTBQueue (coerce requestQueue) (SubRequest (Topic ["#"]) (ResponseQueue pubHistoryResponseQueue, getSockAddr))
  forkIO $ runHistory (ResponseQueue pubHistoryResponseQueue) messagesHistory
  WS.runServer "127.0.0.1" 9160 $ application requestQueue state messagesHistory

convertMessage :: Response -> Maybe MessageData
convertMessage response =
  case response of
    PubResponse (Topic topic') (Message message') (Timestamp timestamp) ->
      Just
        MessageData
          { MessageData.topic = topic',
            MessageData.message = BSU.toString $ B64.encode message',
            MessageData.timestamp = timestamp
          }
    _ -> Nothing

runHistory :: ResponseQueue -> IORef [MessageData] -> IO ()
runHistory (ResponseQueue queue) ref = do
  forever $ do
    newMessage <- atomically $ readTBQueue queue
    oldMessages <- readIORef ref
    case convertMessage newMessage of
      Just message' ->
        writeIORef ref (oldMessages ++ [message'])
      _ ->
        return ()

getSockAddr :: SockAddr
getSockAddr = SockAddrUnix "WS"

application :: RequestQueue -> MVar ServerState -> IORef [MessageData] -> WS.ServerApp
application requestQueue state messagesHistory pending = do
  conn <- WS.acceptRequest pending
  WS.withPingThread conn 30 (return ()) $ do
    pubResponseQueue <- atomically $ newTBQueue 1000
    uuid <- nextRandom
    _ <- atomically $ writeTBQueue (coerce requestQueue) (SubRequest (Topic ["#"]) (ResponseQueue pubResponseQueue, getSockAddr))

    -- Fork a listening thread
    let client = (uuid, conn)
    requestHandler <- forkIO (handleRequests requestQueue conn)

    flip finally (disconnect client pubResponseQueue requestHandler) $ do
      modifyMVar_ state $ \s -> do
        let s' = addClient client s
        history <- readIORef messagesHistory
        mapM_ (WS.sendTextData conn . encode) history
        t <- epoch
        WS.sendTextData conn . encode $ MessageData ["_meta", "history", "end", ""] (BSU.toString $ B64.encode "true") t
        return s'
      talk (ResponseQueue pubResponseQueue) client state
  where
    disconnect conn pubResponseQueue requestHandler = do
      _ <- atomically $ writeTBQueue (coerce requestQueue) (UnsubAllRequest (ResponseQueue pubResponseQueue, getSockAddr))
      _ <- killThread requestHandler
      modifyMVar state $ \s ->
        let s' = removeClient conn s in return (s', s')

talk :: ResponseQueue -> Client -> MVar ServerState -> IO ()
talk (ResponseQueue pubResponseQueue) (_, conn) state = forever $ do
  newMessage <- atomically $ readTBQueue pubResponseQueue
  case convertMessage newMessage of
    Just message -> do
      _ <- putStrLn $ "Send msg: " ++ (show message)
      WS.sendTextData conn $ encode message
    _ ->
      return ()

sendStats :: ResponseQueue -> RequestQueue -> WS.Connection -> IO ()
sendStats statsResponseQueue requestQueue conn = do
  _ <- atomically $ writeTBQueue (coerce requestQueue) (StatsRequest statsResponseQueue)
  stats <- atomically $ readTBQueue (coerce statsResponseQueue)
  case stats of
    StatsResponse stats' -> do
      t <- epoch
      WS.sendTextData conn . encode $ MessageData ["_meta", "stats", ""] (LBSU.toString $ encode stats') t
    _ ->
      putStrLn "Error sending stats via websocket!"

handleRequests :: RequestQueue -> WS.Connection -> IO ()
handleRequests requestQueue conn = do
  statsResponseQueue <- atomically $ newTBQueue 1
  forever $ do
    request <- WS.receiveData conn
    let message = decode request :: Maybe MessageData
    case message of
      Just (MessageData topic message _) ->
        sendStats (ResponseQueue statsResponseQueue) requestQueue conn
      Nothing ->
        return ()
