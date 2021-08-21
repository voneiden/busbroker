{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternSynonyms #-}

module Net (runTCPServer) where

import AlterRoute (AlterRoute (AddRoute, DropRoute), AlterRouteQueue)
import Control.Concurrent (forkFinally, forkIO)
import Control.Concurrent.STM (atomically)
import Control.Concurrent.STM.TBQueue (newTBQueue)
import qualified Control.Exception as E
import Control.Monad (forever, unless, void)
import qualified Data.ByteString as BS
import Data.Word (Word8)
import Network.Socket (Socket)
import qualified Network.Socket as Socket
import qualified Network.Socket.ByteString as BS (recv, sendAll)
import Publish (Publish (Publish), PublishQueue (PublishQueue), RoutePublishQueue)
import qualified Publish (Publish (message))
import qualified Queue as Q
import Data.ByteString.UTF8 as BSU

runTCPServer :: Maybe Socket.HostName -> Socket.ServiceName -> AlterRouteQueue -> RoutePublishQueue -> IO a
runTCPServer host port alterRoute routePublish = Socket.withSocketsDo $ do
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
      E.bracketOnError (Socket.accept sock) (Socket.close . fst) $
        \(connection, _peer) ->
          void $
            -- 'forkFinally' alone is unlikely to fail thus leaking @conn@,
            -- but 'E.bracketOnError' above will be necessary if some
            -- non-atomic setups (e.g. spawning a subprocess to handle
            -- @conn@) before proper cleanup of @conn@ is your case
            forkFinally (connectionManager connection alterRoute routePublish) (const $ Socket.gracefulClose connection 5000)

connectionManager :: Socket -> AlterRouteQueue -> RoutePublishQueue -> IO ()
connectionManager socket alterRoute routePublish = do
  publish <- atomically $ PublishQueue <$> newTBQueue 1000
  -- fork publish queue
  -- TODO THREAD needs to be killed somehow
  _ <- forkIO (relay publish)
  loop publish
  where
    loop :: PublishQueue -> IO ()
    loop publish = do
      msg <- BS.recv socket 1024
      unless (BS.null msg) $ do
        validateRequest (BS.uncons msg) alterRoute routePublish publish
        BS.sendAll socket "ok"
        loop publish

    relay :: PublishQueue -> IO ()
    relay publish = do
      msg <- atomically $ Q.recv publish
      BS.sendAll socket (BSU.fromString $ Publish.message msg)
      relay publish

pattern CmdAddRoute :: (Eq a, Num a) => a
pattern CmdAddRoute = 33

pattern CmdDropRoute :: (Eq a, Num a) => a
pattern CmdDropRoute = 34

pattern CmdRoutePublish :: (Eq a, Num a) => a
pattern CmdRoutePublish = 35

validateRequest :: Maybe (Word8, ByteString) -> AlterRouteQueue -> RoutePublishQueue -> PublishQueue -> IO ()
validateRequest Nothing _ _ _ = return ()
validateRequest (Just (command, _payload)) alterRoute routePublish publish | payloadLength > 0 = handleRequest command _payload alterRoute routePublish publish
                                                                           | otherwise = putStrLn "Bad request (payload length)"
  where payloadLength = BS.length _payload

handleRequest :: Word8 -> ByteString -> AlterRouteQueue -> RoutePublishQueue -> PublishQueue -> IO ()
handleRequest CmdAddRoute _payload alterRoute _ publish = do
  putStrLn $ "Add route: " ++ BSU.toString _payload
  atomically $ Q.send alterRoute (AddRoute (BSU.toString _payload) publish)
handleRequest CmdDropRoute _payload alterRoute _ publish = atomically $ Q.send alterRoute (DropRoute publish)
handleRequest CmdRoutePublish _payload _ routePublish _ = atomically $ Q.send routePublish (Publish "test" "foo") -- TODO parse publish
handleRequest _ _ _ _ _ = putStrLn "Unknown request"
