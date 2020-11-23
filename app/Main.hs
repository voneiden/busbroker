{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Main where

import Control.Concurrent (forkIO, killThread, threadDelay)
import Control.Concurrent.STM (STM, atomically)
import Control.Concurrent.STM.TBQueue (TBQueue, newTBQueue, readTBQueue, writeTBQueue)
import qualified Data.List as List (filter)
import Data.List.Split (splitOn)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Queues.Publish (PublishMessage (PublishMessage), PublishQueue (PublishQueue), DeliveryQueue (DeliveryQueue))
import qualified Queues.Publish as PublishMessage (PublishMessage (..))
import Queues.AlterRoute (AlterRouteMessage (AddRouteMessage, DropRouteMessage), topic, queue, AlterRouteQueue (AlterRouteQueue))
import Control.Monad (forM_)
import qualified Queues.Queue as Q (recv, send)
import RouteMap (RouteMap (RouteMap), findRoutes)
import Data.Coerce (coerce)
--import qualified Types.SubMessage.ModifyRouteMessage as SubMessage (SubMessage (..))

maybeList :: [a] -> Maybe [a]
maybeList [] = Nothing
maybeList x = Just x

routePub :: RouteMap -> PublishQueue -> STM ()
routePub routeMap publishQueue = do
  msg <- Q.recv publishQueue
  _ <- case findRoutes routeMap msg of
    [] -> return ()
    routes -> foldl1 (>>) $ map (route (PublishMessage.topic msg) (PublishMessage.message msg)) routes
  return ()
  where
    route :: String -> String -> DeliveryQueue -> STM ()
    route topic message routeQueue = Q.send routeQueue (PublishMessage topic message)


router :: RouteMap -> PublishQueue -> IO ()
router routeMap pubQueue = do
  print ("Start router")
  _ <- atomically (routePub routeMap pubQueue)
  print ("Got pub")
  router routeMap pubQueue
  print("Routed")


-- |
--  Process SubMessage
--
resolveSubRequest :: AlterRouteMessage -> RouteMap -> RouteMap
resolveSubRequest AddRouteMessage{..} (RouteMap routeMap) = RouteMap $ Map.insertWith (++) topic [queue] routeMap
resolveSubRequest DropRouteMessage{..} (RouteMap routeMap) = RouteMap $ Map.mapMaybe (maybeList . List.filter (/=queue)) routeMap

-- |
--  routerManager is responsible for maintaining a route map and the router thread
--  It takes one argument, of type 'Int'.
routerManager :: RouteMap -> AlterRouteQueue -> PublishQueue -> IO ()
routerManager routeMap alterRouteQueue pubQueue = do
  print ("Start routerManager")
  print (Map.keys (coerce routeMap :: Map String [DeliveryQueue]))
  routerThreadId <- forkIO $ router routeMap pubQueue
  subRequest <- atomically $ Q.recv alterRouteQueue
  killThread routerThreadId
  print("Alter route received")
  routerManager (resolveSubRequest subRequest routeMap) alterRouteQueue pubQueue

test :: AlterRouteQueue -> PublishQueue -> IO ()
test alterRouteQueue publishQueue = do
  route <- atomically $ DeliveryQueue <$> newTBQueue 1000
  _ <- atomically $ Q.send alterRouteQueue (AddRouteMessage "test" route)
  threadDelay 100
  _ <- atomically $ Q.send publishQueue (PublishMessage "test" "Hello world")
  result <- atomically $ Q.recv route
  print $ PublishMessage.message result
  _ <- atomically $ Q.send alterRouteQueue (AddRouteMessage "test/+/kikki" route)
  threadDelay 100
  _ <- atomically $ Q.send publishQueue (PublishMessage "test/foo/kikki" "Hello kikki")
  print("Waiting for response vvv")
  result <- atomically $ Q.recv route
  print("Got response")
  print $ PublishMessage.message result
  _ <- atomically $ Q.send alterRouteQueue (DropRouteMessage route)
  return ()

main :: IO ()
main = do
  alterRouteQueue <- atomically $ AlterRouteQueue <$> newTBQueue 1000
  publishQueue <- atomically $ PublishQueue <$> newTBQueue 1000
  _ <- forkIO $ test alterRouteQueue publishQueue
  routerManager (RouteMap Map.empty) alterRouteQueue publishQueue
  return ()

