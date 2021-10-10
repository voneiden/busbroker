{-# LANGUAGE OverloadedStrings #-}

module WebSocket where

import Control.Concurrent (MVar, forkIO, modifyMVar, modifyMVar_, newMVar, readMVar)
import Control.Concurrent.STM (atomically, flushTBQueue, newTBQueue, peekTBQueue, readTBQueue, writeTBQueue)
import Control.Exception (finally)
import Control.Monad (forM_, forever)
import Data.Aeson (ToJSON, encode)
import Data.ByteString.Base64 (decodeLenient)
import qualified Data.ByteString.Base64 as B64
import qualified Data.ByteString.UTF8 as BSU
import Data.Char (isPunctuation, isSpace)
import Data.Coerce (coerce)
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.List as List
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.IO as Text
import Data.UUID (UUID)
import Data.UUID.V4 (nextRandom)
import MessageData
import Network.Socket (SockAddr (SockAddrUnix))
import qualified Network.WebSockets as WS
import RouterTypes
import Util (epoch)

instance ToJSON MessageData

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
    let client = (uuid, conn)
    flip finally (disconnect client pubResponseQueue) $ do
      modifyMVar_ state $ \s -> do
        let s' = addClient client s
        history <- readIORef messagesHistory
        mapM_ (WS.sendTextData conn . encode) history
        timestamp <- epoch
        WS.sendTextData conn . encode $ MessageData ["_meta", "history", "end", ""] (BSU.toString $ B64.encode "true") timestamp
        return s'
      talk (ResponseQueue pubResponseQueue) client state
  where
    disconnect conn pubResponseQueue = do
      _ <- atomically $ writeTBQueue (coerce requestQueue) (UnsubAllRequest (ResponseQueue pubResponseQueue, getSockAddr))
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
