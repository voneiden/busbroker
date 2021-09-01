{-# LANGUAGE OverloadedStrings #-}

module Net (runTCPServer) where

import Control.Concurrent (forkFinally, forkIO)
import Control.Concurrent.STM (atomically, readTBQueue, writeTBQueue)
import Control.Concurrent.STM.TBQueue (newTBQueue)
import qualified Control.Exception as E
import Control.Monad (forever, void)
import qualified Data.ByteString as BS
import Data.ByteString.UTF8 (ByteString)
import qualified Data.ByteString.UTF8 as BSU
import Data.Char (chr)
import Data.Coerce (coerce)
import Network.Socket (Socket, getPeerName, SockAddr)
import qualified Network.Socket as Socket
import qualified Network.Socket.ByteString as SBS (recv, sendAll)
import RouterTypes
import Data.List.Split (splitOn)
import Data.List (intercalate)

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
            forkFinally (runQueueHandlers connection requestQueue responseQueue) (closeConnection requestQueue responseQueue connection)

toLengthPrefixedFrame :: ByteString -> Maybe ByteString
toLengthPrefixedFrame bs
  | bsLength > 255 = Nothing
  | otherwise = Just $ BS.append (BS.singleton (fromIntegral bsLength)) bs
  where
    bsLength = BS.length bs

sendResponse :: Socket -> Response -> IO ()
sendResponse socket (PubResponse (Topic topic) (Message message)) =
  case toLengthPrefixedFrame (BSU.fromString $ intercalate "/" topic) of
    Just bsTopic ->
      case toLengthPrefixedFrame message of
        Just bsMessage ->
          SBS.sendAll socket (BS.concat ["@", bsTopic, bsMessage])
        Nothing ->
          ioError $ userError "Message too long to publish"
    Nothing ->
      ioError $ userError "Topic too long to publish"

runQueueHandlers :: Socket -> RequestQueue -> ResponseQueue -> IO ()
runQueueHandlers socket requestQueue responseQueue = do
  addr <- getPeerName socket
  _ <- forkIO (forever $ deliverMessage socket addr responseQueue)
  forever $ receiveMessage socket addr requestQueue responseQueue

deliverMessage :: Socket -> SockAddr -> ResponseQueue -> IO ()
deliverMessage socket addr responseQueue = do
  response <- atomically $ readTBQueue (coerce responseQueue)
  sendResponse socket response

recvNBytes' :: Socket -> Int -> IO [ByteString]
recvNBytes' socket n
  | n > 0 = do
    bytes <- SBS.recv socket n
    if BS.null bytes
      then ioError $ userError "Socket closed"
      else do
        let missingBytes = n - BS.length bytes
        if missingBytes > 0
          then do
            rest <- recvNBytes' socket missingBytes
            return $ bytes : rest
          else return [bytes]
  | otherwise = ioError $ userError "n must be more than zero"

recvNBytes :: Socket -> Int -> IO ByteString
recvNBytes socket n = do
  bytestrings <- recvNBytes' socket n
  return $ BS.concat bytestrings

readLengthPrefixedFrame :: Socket -> IO ByteString
readLengthPrefixedFrame socket = do
  n <- recvNBytes socket 1
  recvNBytes socket (fromIntegral $ BS.head n)

receiveMessage :: Socket -> SockAddr -> RequestQueue -> ResponseQueue -> IO ()
receiveMessage socket addr requestQueue responseQueue = do
  command <- recvNBytes socket 1
  handleRequest socket addr (chr . fromEnum $ BS.head command) requestQueue responseQueue

handleRequest :: Socket -> SockAddr -> Char -> RequestQueue -> ResponseQueue -> IO ()
handleRequest socket addr '+' requestQueue responseQueue = do
  topicPattern <- readLengthPrefixedFrame socket
  atomically $ writeTBQueue (coerce requestQueue) (SubRequest (Topic (splitOn "/" $ BSU.toString topicPattern)) responseQueue)
handleRequest socket addr '-' requestQueue responseQueue = do
  topicPattern <- readLengthPrefixedFrame socket
  atomically $ writeTBQueue (coerce requestQueue) (UnsubRequest (Topic (splitOn "/" $ BSU.toString topicPattern)) responseQueue)
handleRequest socket addr '@' requestQueue _ = do
  topic <- readLengthPrefixedFrame socket
  message <- readLengthPrefixedFrame socket
  atomically $ writeTBQueue (coerce requestQueue) (PubRequest addr (Topic (splitOn "/" $ BSU.toString topic)) (Message message))
handleRequest _ _ _ _ _ = ioError $ userError "Unknown command"
