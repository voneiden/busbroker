module Router (runRouter) where

import Control.Concurrent.STM (STM, atomically, readTBQueue, writeTBQueue)
import Data.Coerce (coerce)
import qualified Data.List as List (filter)
import Data.List.Split (splitOn)
import qualified Data.Map.Strict as Map
import RouterTypes
import System.TimeIt (timeItNamed)
import Util (epoch)
import Network.Socket (SockAddr)
import Stats

matchTopic :: Topic -> Topic -> Bool
matchTopic (Topic subTopic) (Topic pubTopic) = matchTopic' subTopic pubTopic
  where
    matchTopic' :: [String] -> [String] -> Bool
    matchTopic' ("#" : _) _ = True -- Multi-level wildcard
    matchTopic' ("+" : ss) (_ : ps) = matchTopic' ss ps -- Single-level wildcard
    matchTopic' (s : ss) (p : ps) = s == p && matchTopic' ss ps -- Regular level match
    matchTopic' [] [] = True -- Fully matched
    matchTopic' _ _ = False -- otherwise: mismatch

findRoutes :: RouteMap -> Topic -> [ResponseQueue]
findRoutes (RouteMap routeMap) topic = do
  concat $ Map.elems $ Map.filterWithKey f routeMap
  where
    f :: Topic -> [ResponseQueue] -> Bool
    f subTopic _ = matchTopic subTopic topic

findRoutesIO :: RouteMap -> Topic -> IO [ResponseQueue]
findRoutesIO routeMap topic = return $ findRoutes routeMap topic
--
sendResponses :: Response -> [ResponseQueue] -> STM ()
sendResponses _ [] = return ()
sendResponses response responseQueues = foldl1 (>>) $ map (($ response) . writeTBQueue) (coerce responseQueues)

maybeList :: [a] -> Maybe [a]
maybeList [] = Nothing
maybeList x = Just x

unsubMapper :: Topic -> ResponseQueue -> Topic -> [ResponseQueue] -> Maybe [ResponseQueue]
unsubMapper unsubTopic unsubResponseQueue topic responseQueues
  | unsubTopic == topic = maybeList $ List.filter (/= unsubResponseQueue) responseQueues
  | otherwise = Just responseQueues


handleRequest :: Request -> RouteMap -> QueueStatisticsMap -> IO (RouteMap, QueueStatisticsMap)
handleRequest (SubRequest subTopic subResponseQueue) (RouteMap routeMap) queueStatisticsMap = do
  return (RouteMap $ Map.insertWith (++) subTopic [subResponseQueue] routeMap, queueStatisticsMap)

handleRequest (UnsubRequest unsubTopic unsubResponseQueue) (RouteMap routeMap) queueStatisticsMap = do
  return (RouteMap $ Map.mapMaybeWithKey (unsubMapper unsubTopic unsubResponseQueue) routeMap, queueStatisticsMap)

handleRequest (UnsubAllRequest unsubAllResponseQueue) (RouteMap routeMap) queueStatisticsMap = do
  return (RouteMap $ Map.mapMaybe (maybeList . List.filter (/= unsubAllResponseQueue)) routeMap, queueStatisticsMap)

handleRequest (PubRequest addr topic message) routeMap queueStatisticsMap = do
  queueStatisticsMap' <- recordStatsOut addr queueStatisticsMap
  _ <- atomically $ sendResponses (PubResponse topic message) $ findRoutes routeMap topic
  --putStrLn $ "Delivered to " ++ show (length routes) ++ " queues"
  return (routeMap, queueStatisticsMap')

handleRequest (IdentifyRequest addr name) routeMap queueStatisticsMap = do
  queueStatisticsMap' <- recordStatsName addr queueStatisticsMap name
  return (routeMap, queueStatisticsMap')
  
handleRequest (PongRequest addr pong) routeMap queueStatisticsMap = do
  queueStatisticsMap' <- recordStatsPing addr queueStatisticsMap pong
  return (routeMap, queueStatisticsMap')

router :: RequestQueue -> RouteMap -> QueueStatisticsMap -> IO ()
router (RequestQueue requestQueue) routeMap queueStatisticsMap = do
  --putStrLn "Router waiting for messages"
  request <- atomically $ readTBQueue requestQueue
  (routeMap', queueStatisticsMap') <- handleRequest request routeMap queueStatisticsMap
  print queueStatisticsMap'
  --putStrLn "Processing done"
  router (RequestQueue requestQueue) routeMap' queueStatisticsMap'

runRouter :: RequestQueue -> IO ()
runRouter requestQueue =
  router requestQueue (RouteMap Map.empty) (QueueStatisticsMap Map.empty)
