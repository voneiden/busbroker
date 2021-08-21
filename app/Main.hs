{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Main where

import AlterRoute (AlterRoute (AddRoute, DropRoute), AlterRouteQueue (AlterRouteQueue))
import qualified AlterRoute (AlterRoute (..))
import Control.Concurrent (forkIO, killThread, threadDelay)
import Control.Concurrent.STM (STM, atomically)
import Control.Concurrent.STM.TBQueue (newTBQueue)
import Data.Coerce (coerce)
import qualified Data.List as List (filter)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Publish (Publish (Publish), PublishQueue (PublishQueue), RoutePublishQueue (RoutePublishQueue))
import qualified Publish (Publish (..))
import qualified Queue as Q (recv, send)
import RouteMap (RouteMap (RouteMap), findRoutes)
import Net (runTCPServer)
--import qualified Types.SubMessage.ModifyRouteMessage as SubMessage (SubMessage (..))

maybeList :: [a] -> Maybe [a]
maybeList [] = Nothing
maybeList x = Just x

routerPublish :: RouteMap -> RoutePublishQueue -> STM ()
routerPublish routeMap publishQueue = do
  msg <- Q.recv publishQueue
  _ <- case findRoutes routeMap msg of
    [] -> return ()
    routes -> foldl1 (>>) $ map (route (Publish.topic msg) (Publish.message msg)) routes
  return ()
  where
    route :: String -> String -> PublishQueue -> STM ()
    route topic message routeQueue = Q.send routeQueue (Publish topic message)

router :: RouteMap -> RoutePublishQueue -> IO ()
router routeMap pubQueue = do
  _ <- atomically (routerPublish routeMap pubQueue)
  router routeMap pubQueue

routeManager :: RouteMap -> AlterRouteQueue -> RoutePublishQueue -> IO ()
routeManager routeMap alterRouteQueue pubQueue = do
  print (Map.keys (coerce routeMap :: Map String [PublishQueue]))
  routerThreadId <- forkIO $ router routeMap pubQueue
  subRequest <- atomically $ Q.recv alterRouteQueue
  killThread routerThreadId
  routeManager (processRequest subRequest) alterRouteQueue pubQueue
  where
    processRequest :: AlterRoute -> RouteMap
    processRequest AddRoute {..} = RouteMap $ Map.insertWith (++) topic [queue] (coerce routeMap)
    processRequest DropRoute {..} = RouteMap $ Map.mapMaybe (maybeList . List.filter (/= queue)) (coerce routeMap)

test :: AlterRouteQueue -> RoutePublishQueue -> IO ()
test alterRouteQueue publishQueue = do
  route <- atomically $ PublishQueue <$> newTBQueue 1000
  _ <- atomically $ Q.send alterRouteQueue (AddRoute "test" route)
  threadDelay 100
  _ <- atomically $ Q.send publishQueue (Publish "test" "Hello world")
  _ <- atomically $ Q.recv route :: IO Publish
  _ <- atomically $ Q.send alterRouteQueue (AddRoute "test/+/kikki" route)
  threadDelay 100
  _ <- atomically $ Q.send publishQueue (Publish "test/foo/kikki" "Hello kikki")
  _ <- atomically $ Q.recv route :: IO Publish
  _ <- atomically $ Q.send alterRouteQueue (DropRoute route)
  return ()

main :: IO ()
main = do
  alterRoute <- atomically $ AlterRouteQueue <$> newTBQueue 1000
  routePublish <- atomically $ RoutePublishQueue <$> newTBQueue 1000
  --_ <- forkIO $ test alterRoute routePublish
  _ <- forkIO $ routeManager (RouteMap Map.empty) alterRoute routePublish
  _ <- runTCPServer Nothing "42069" alterRoute routePublish
  return ()
