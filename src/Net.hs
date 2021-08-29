{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternSynonyms #-}

module Net (runTCPServer) where

import Control.Concurrent (forkFinally, forkIO)
import Control.Concurrent.STM (atomically, readTBQueue, writeTBQueue)
import Control.Concurrent.STM.TBQueue (newTBQueue)
import qualified Control.Exception as E
import Control.Monad (forever, unless, void)
import qualified Data.ByteString as BS
import Data.ByteString.UTF8 (ByteString)
import qualified Data.ByteString.UTF8 as BSU
import Data.Coerce (coerce)
import Data.Word (Word8)
import Network.Socket (Socket)
import qualified Network.Socket as Socket
import qualified Network.Socket.ByteString as SBS (recv, sendAll)
import RouterTypes

-- TOOD use https://hackage.haskell.org/package/network-simple/docs/Network-Simple-TCP.html ?

closeConnection :: RequestQueue -> ResponseQueue -> Socket -> b -> IO ()
closeConnection requestQueue responseQueue connection _ = do
  _ <- atomically $ writeTBQueue (coerce requestQueue) (UnsubAllRequest responseQueue)
  Socket.gracefulClose connection 5000

runTCPServer :: Maybe Socket.HostName -> Socket.ServiceName -> RequestQueue -> IO a
runTCPServer host port requestQueue = Socket.withSocketsDo $ do
  addr <- resolve
  E.bracket (open addr) Socket.close loop
  where
    resolve = do
      let hints =
            Socket.defaultHints
              { Socket.addrFlags = [Socket.AI_PASSIVE],
                Socket.addrSocketType = Socket.Stream
              }
      head <$> Socket.getAddrInfo (Just hints) host (Just port)
    open addr = E.bracketOnError (Socket.openSocket addr) Socket.close $ \socket -> do
      putStrLn $ "Open add" ++ show addr
      Socket.setSocketOption socket Socket.ReuseAddr 1
      Socket.withFdSocket socket Socket.setCloseOnExecIfNeeded
      Socket.bind socket $ Socket.addrAddress addr
      Socket.listen socket 5
      return socket
    loop sock = forever $
      -- TODO close should lead to unsub
      E.bracketOnError (Socket.accept sock) (Socket.close . fst) $
        \(connection, _peer) -> do
          responseQueue <- atomically $ ResponseQueue <$> newTBQueue 1000
          void $
            -- 'forkFinally' alone is unlikely to fail thus leaking @conn@,
            -- but 'E.bracketOnError' above will be necessary if some
            -- non-atomic setups (e.g. spawning a subprocess to handle
            -- @conn@) before proper cleanup of @conn@ is your case
            forkFinally (connectionManager connection requestQueue responseQueue) (closeConnection requestQueue responseQueue connection)

receiveByte :: Socket -> IO [Word8]
receiveByte socket = do
  byte <- SBS.recv socket 1
  if BS.null byte
    then return []
    else return [BS.last byte]

receiveMessage' :: Socket -> [Word8] -> IO [Word8]
receiveMessage' _ [] = return []
receiveMessage' _ [0] = return [0]
receiveMessage' socket lastByte = do
  nextByte <- receiveByte socket
  nextData <- receiveMessage' socket nextByte
  if null nextData
    then return []
    else return $ lastByte ++ nextData

receiveMessage :: Socket -> IO ByteString
receiveMessage socket = do
  firstByte <- receiveByte socket
  message <- receiveMessage' socket firstByte
  return $ BS.pack message

sendResponse :: Socket -> Response -> IO ()
sendResponse socket (PubResponse (Topic topic) (Message message)) =
  SBS.sendAll socket (BSU.fromString $ topic ++ "|" ++ message ++ "\0")

connectionManager :: Socket -> RequestQueue -> ResponseQueue -> IO ()
connectionManager socket requestQueue responseQueue = do
  _ <- forkIO (deliverToClient responseQueue)
  receiveFromClient responseQueue
  where
    receiveFromClient :: ResponseQueue -> IO ()
    receiveFromClient responseQueue = do
      msg <- receiveMessage socket
      unless (BS.null msg) $ do
        validateRequest (BS.uncons $ stripTrailingNull msg) requestQueue responseQueue
        receiveFromClient responseQueue

    deliverToClient :: ResponseQueue -> IO ()
    deliverToClient responseQueue = do
      response <- atomically $ readTBQueue (coerce responseQueue)
      _ <- sendResponse socket response
      deliverToClient responseQueue

pattern CmdAddRoute :: (Eq a, Num a) => a
pattern CmdAddRoute = 43 -- plus

pattern CmdDropRoute :: (Eq a, Num a) => a
pattern CmdDropRoute = 45 -- minus

pattern CmdRoutePublish :: (Eq a, Num a) => a
pattern CmdRoutePublish = 64 -- @

stripTrailingNull' :: ByteString -> Maybe (Word8, ByteString) -> ByteString
stripTrailingNull' _ (Just (0, restReversed)) = BS.reverse restReversed
stripTrailingNull' bs _ = bs

stripTrailingNull :: ByteString -> ByteString
stripTrailingNull bs = stripTrailingNull' bs (BS.uncons $ BS.reverse bs)

validateRequest :: Maybe (Word8, ByteString) -> RequestQueue -> ResponseQueue -> IO ()
validateRequest Nothing _ _ = return ()
validateRequest (Just (command, _payload)) requestQueue responseQueue
  | payloadLength > 0 = handleRequest command _payload requestQueue responseQueue
  | otherwise = putStrLn "Bad request (payload length)"
  where
    payloadLength = BS.length _payload

handleRoutePublish :: RequestQueue -> [String] -> IO()
handleRoutePublish requestQueue [topic, message] = atomically $ writeTBQueue (coerce requestQueue) (PubRequest (Topic topic) (Message message))
handleRoutePublish _ _ = do
  putStrLn "Invalid data in publish"
  return ()

-- TODO use Char8 https://hackage.haskell.org/package/bytestring-0.9.2.1/docs/Data-ByteString-Char8.html
handleRequest :: Word8 -> ByteString -> RequestQueue -> ResponseQueue -> IO ()
handleRequest CmdAddRoute _payload requestQueue responseQueue = do
  putStrLn $ "Add route: " ++ BSU.toString _payload
  atomically $ writeTBQueue (coerce requestQueue) (SubRequest (Topic (BSU.toString _payload)) responseQueue)
handleRequest CmdDropRoute _payload requestQueue responseQueue = do
  putStrLn $ "Drop route: " ++ BSU.toString _payload
  atomically $ writeTBQueue (coerce requestQueue) (UnsubRequest (Topic (BSU.toString _payload)) responseQueue)
handleRequest CmdRoutePublish _payload requestQueue _ = do
  putStrLn $ "Publish message: " ++ BSU.toString _payload
  handleRoutePublish requestQueue (map BSU.toString $ BS.split 124 _payload)
handleRequest cmd _payload _ _ = putStrLn $ "Unknown request: " ++ show cmd ++ show _payload
