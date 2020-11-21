{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Main where

import Control.Concurrent (forkIO, killThread)
import Control.Concurrent.STM (STM, atomically)
import Control.Concurrent.STM.TBQueue (TBQueue, newTBQueue, readTBQueue, writeTBQueue)
import Data.List.Split (splitOn)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Types.PubMessage (PubMessage (PubMessage))
import qualified Types.PubMessage as PubMessage (PubMessage (..))
import Types.RouteMessage (RouteMessage (RouteMessage))
import qualified Types.RouteMessage as RouteMessage (RouteMessage (..))
import Types.SubMessage (SubMessage (SubMessage, UnsubMessage))
import qualified Types.SubMessage as SubMessage (SubMessage (..))
-- |
--  MQTT style topic matching.
matchTopic :: String -> String -> Bool
matchTopic subTopic pubTopic = matchTopic' (splitOn "/" subTopic) (splitOn "/" pubTopic)
  where
    matchTopic' :: [String] -> [String] -> Bool
    matchTopic' ("#" : _) _ = True                              -- Multi-level wildcard
    matchTopic' ("+" : ss) (_ : ps) = matchTopic' ss ps         -- Single-level wildcard
    matchTopic' (s : ss) (p : ps) = s == p && matchTopic' ss ps -- Regular level match
    matchTopic' [] [] = True                                    -- Fully matched
    matchTopic' _ _ = False                                     -- otherwise: mismatch

findRoutes :: Map String [TBQueue RouteMessage] -> PubMessage -> [TBQueue RouteMessage]
findRoutes clientRouteMap msg = do
  concat $ Map.elems $ Map.filterWithKey f clientRouteMap
  where
    f :: String -> [TBQueue RouteMessage] -> Bool
    f subTopic _ = matchTopic subTopic pubTopic
      where
        pubTopic = PubMessage.topic msg

routePub :: Map String [TBQueue RouteMessage] -> TBQueue PubMessage -> STM ()
routePub clientRouteMap pubQueue = do
  -- TBQueue RouteMessage
  msg <- readTBQueue pubQueue
  let routes = findRoutes clientRouteMap msg
  _ <- foldl1 (>>) $ map (route (PubMessage.topic msg) (PubMessage.message msg)) routes
  return ()
  where
    route :: String -> String -> TBQueue RouteMessage -> STM ()
    route topic message routeQueue = writeTBQueue routeQueue (RouteMessage topic message)


router :: Map String [TBQueue RouteMessage] -> TBQueue PubMessage -> IO ()
router clientRouteMap pubQueue = do
  print ("Start router")
  _ <- atomically (routePub clientRouteMap pubQueue)
  print ("Got pub")
  router clientRouteMap pubQueue


resolveSubRequest :: SubMessage -> Map String [TBQueue RouteMessage] -> Map String [TBQueue RouteMessage]
resolveSubRequest SubMessage{..} clientRouteMap = Map.insertWith (++) topic [queue] clientRouteMap
resolveSubRequest UnsubMessage{..} clientRouteMap = Map.mapMaybe removeUnsubbed clientRouteMap
  where
    removeUnsubbed :: [TBQueue RouteMessage] -> Maybe [TBQueue RouteMessage]
    removeUnsubbed queues = allOrNothing $ skipMatch queues
      where
        skipMatch :: [TBQueue RouteMessage] -> [TBQueue RouteMessage]
        skipMatch [] = []
        skipMatch (rm:rms)
          | rm == queue = skipMatch rms
          | otherwise = rm : skipMatch rms
        allOrNothing :: [TBQueue RouteMessage] -> Maybe [TBQueue RouteMessage]
        allOrNothing [] = Nothing
        allOrNothing x = Just x
-- |
--  routerManager is responsible for maintaining a route map and the router thread
--  It takes one argument, of type 'Int'.
routerManager :: Map String [TBQueue RouteMessage] -> TBQueue SubMessage -> TBQueue PubMessage -> IO ()
routerManager clientRouteMap subQueue pubQueue = do
  print ("Start routerManager")
  print (Map.keys clientRouteMap)
  routerThreadId <- forkIO $ router clientRouteMap pubQueue
  subRequest <- atomically (readTBQueue subQueue)
  killThread routerThreadId
  routerManager (resolveSubRequest subRequest clientRouteMap) subQueue pubQueue

test :: TBQueue SubMessage -> TBQueue PubMessage -> IO ()
test subQueue pubQueue = do
  route <- atomically $ newTBQueue 1000
  _ <- atomically $ writeTBQueue subQueue (SubMessage "test" route)
  _ <- atomically $ writeTBQueue pubQueue (PubMessage "test" "Hello world")
  result <- atomically $ readTBQueue route
  print $ RouteMessage.message result
  _ <- atomically $ writeTBQueue subQueue (SubMessage "test/+/kikki" route)
  _ <- atomically $ writeTBQueue pubQueue (PubMessage "test/foo/kikki" "Hello kikki")
  result <- atomically $ readTBQueue route
  print $ RouteMessage.message result
  _ <- atomically $ writeTBQueue subQueue (UnsubMessage route)
  return ()

main :: IO ()
main = do
  subQueue <- atomically $ newTBQueue 1000
  pubQueue <- atomically $ newTBQueue 1000
  _ <- forkIO $ test subQueue pubQueue
  routerManager Map.empty subQueue pubQueue
  print "OK"
  return ()


-- todo verkkoserveri
