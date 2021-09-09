module Router (runRouter) where

import Control.Concurrent.STM (STM, atomically, readTBQueue, writeTBQueue)
import Data.Coerce (coerce)
import qualified Data.List as List (filter, delete, map)
import Data.List.Split (splitOn)
import qualified Data.Map.Strict as Map
import RouterTypes
import System.TimeIt (timeItNamed)
import Util (epoch)
import Network.Socket (SockAddr)
import Stats
import Control.Concurrent (threadDelay, forkIO)
import Control.Monad (forever, foldM)

matchTopic :: Topic -> Topic -> Bool
matchTopic (Topic subTopic) (Topic pubTopic) = matchTopic' subTopic pubTopic
  where
    matchTopic' :: [String] -> [String] -> Bool
    matchTopic' ("#" : _) _ = True -- Multi-level wildcard
    matchTopic' ("+" : ss) (_ : ps) = matchTopic' ss ps -- Single-level wildcard
    matchTopic' (s : ss) (p : ps) = s == p && matchTopic' ss ps -- Regular level match
    matchTopic' [] [] = True -- Fully matched
    matchTopic' _ _ = False -- otherwise: mismatch

findRoutes :: RouteMap -> Topic -> [(ResponseQueue, SockAddr)]
findRoutes (RouteMap routeMap) topic = do
  concat $ Map.elems $ Map.filterWithKey f routeMap
  where
    f :: Topic -> [(ResponseQueue, SockAddr)] -> Bool
    f subTopic _ = matchTopic subTopic topic

findRoutesIO :: RouteMap -> Topic -> IO [(ResponseQueue, SockAddr)]
findRoutesIO routeMap topic = return $ findRoutes routeMap topic
--
sendResponses :: Response -> [ResponseQueue] -> STM ()
sendResponses _ [] = return ()
sendResponses response responseQueues = foldl1 (>>) $ map (($ response) . writeTBQueue) (coerce responseQueues)

maybeList :: [a] -> Maybe [a]
maybeList [] = Nothing
maybeList x = Just x

unsubMapper :: Topic -> (ResponseQueue, SockAddr) -> Topic -> [(ResponseQueue, SockAddr)] -> Maybe [(ResponseQueue, SockAddr)]
unsubMapper unsubTopic unsubResponseQueue topic responseQueues
  | unsubTopic == topic = maybeList $ List.filter (/= unsubResponseQueue) responseQueues
  | otherwise = Just responseQueues

handleRequest :: Request -> RouteMap -> QueueStatisticsMap -> PingResponseQueues -> IO (RouteMap, QueueStatisticsMap, PingResponseQueues)
handleRequest (SubRequest subTopic subResponseQueue) (RouteMap routeMap) queueStatisticsMap pings = do
  return (RouteMap $ Map.insertWith (++) subTopic [subResponseQueue] routeMap, queueStatisticsMap, pings)

handleRequest (UnsubRequest unsubTopic unsubResponseQueue) (RouteMap routeMap) queueStatisticsMap pings = do
  return (RouteMap $ Map.mapMaybeWithKey (unsubMapper unsubTopic unsubResponseQueue) routeMap, queueStatisticsMap, pings)

handleRequest (UnsubAllRequest unsubAllResponseQueue) (RouteMap routeMap) queueStatisticsMap pings = do
  return (RouteMap $ Map.mapMaybe (maybeList . List.filter (/= unsubAllResponseQueue)) routeMap, queueStatisticsMap, pings)

handleRequest (PubRequest addr topic message) routeMap queueStatisticsMap pings = do
  queueStatisticsMap' <- recordStatsOut addr queueStatisticsMap
  let routeSockAddrs = findRoutes routeMap topic
  let routes = List.map fst routeSockAddrs
  let sockAddrs = List.map snd routeSockAddrs
  queueStatisticsMap'' <- foldM (flip recordStatsIn) queueStatisticsMap' sockAddrs
  _ <- atomically $ sendResponses (PubResponse topic message) routes
  return (routeMap, queueStatisticsMap'', pings)

handleRequest (IdentifyRequest addr maybeRequestQueue) routeMap queueStatisticsMap (PingResponseQueues pings) = do
  queueStatisticsMap' <- recordIdentify addr queueStatisticsMap
  let pings' = case maybeRequestQueue of
                  Just queue ->
                    queue : pings
                  Nothing ->
                    pings
  return (routeMap, queueStatisticsMap', PingResponseQueues pings')


handleRequest (UnidentifyRequest addr maybeRequestQueue) routeMap queueStatisticsMap (PingResponseQueues pings) = do
  let pings' = case maybeRequestQueue of
                  Just queue ->
                    List.delete queue pings
                  Nothing ->
                    pings
  return (routeMap, deleteStats addr queueStatisticsMap, PingResponseQueues pings')

handleRequest (PongRequest addr pong) routeMap queueStatisticsMap pings = do
  queueStatisticsMap' <- recordStatsPing addr queueStatisticsMap pong
  return (routeMap, queueStatisticsMap', pings)

handleRequest PingAllRequest routeMap queueStatisticsMap pings = do
  mapM_ pingQueue (coerce pings :: [ResponseQueue])
  return (routeMap, queueStatisticsMap, pings)

handleRequest (StatsRequest responseQueue) routeMap queueStatisticsMap pings = do
  _ <- atomically $ writeTBQueue (coerce responseQueue) (StatsResponse $ Map.elems (coerce queueStatisticsMap))
  return (routeMap, queueStatisticsMap, pings)

router :: RequestQueue -> RouteMap -> QueueStatisticsMap -> PingResponseQueues -> IO ()
router (RequestQueue requestQueue) routeMap stats pings = do
  request <- atomically $ readTBQueue requestQueue
  (routeMap', stats', pings') <- handleRequest request routeMap stats pings
  router (RequestQueue requestQueue) routeMap' stats' pings'

pingAll :: RequestQueue -> IO ()
pingAll (RequestQueue requestQueue)= do
  threadDelay 1000000
  atomically $ writeTBQueue requestQueue PingAllRequest

pingQueue :: ResponseQueue -> IO ()
pingQueue queue = do
  t <- epoch
  atomically $ writeTBQueue (coerce queue) (PingResponse t)

runRouter :: RequestQueue -> IO ()
runRouter requestQueue = do
  _ <- forkIO $ forever $ pingAll requestQueue
  router requestQueue (RouteMap Map.empty) (QueueStatisticsMap Map.empty) (PingResponseQueues [])
