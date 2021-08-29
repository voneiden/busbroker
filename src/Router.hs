module Router (runRouter) where

import Control.Concurrent.STM (STM, atomically, readTBQueue, writeTBQueue)
import Data.Coerce (coerce)
import qualified Data.List as List (filter)
import Data.List.Split (splitOn)
import qualified Data.Map.Strict as Map
import RouterTypes

matchTopic :: Topic -> Topic -> Bool
matchTopic (Topic subTopic) (Topic pubTopic) = matchTopic' (splitOn "/" subTopic) (splitOn "/" pubTopic)
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

handleRequest :: Request -> RouteMap -> IO RouteMap
handleRequest (SubRequest subTopic subResponseQueue) (RouteMap routeMap) = return $ RouteMap $ Map.insertWith (++) subTopic [subResponseQueue] routeMap
handleRequest (UnsubRequest unsubTopic unsubResponseQueue) (RouteMap routeMap) = return $ RouteMap $ Map.mapMaybeWithKey (unsubMapper unsubTopic unsubResponseQueue) routeMap
handleRequest (UnsubAllRequest unsubAllResponseQueue) (RouteMap routeMap) = return $ RouteMap $ Map.mapMaybe (maybeList . List.filter (/= unsubAllResponseQueue)) routeMap
handleRequest (PubRequest topic message) routeMap = do
  _ <- atomically $ sendResponses (PubResponse topic message) (findRoutes routeMap topic)
  return routeMap

router :: RequestQueue -> RouteMap -> IO ()
router (RequestQueue requestQueue) routeMap = do
  putStrLn "Router waiting for messages"
  request <- atomically $ readTBQueue requestQueue
  newRouteMap <- handleRequest request routeMap
  putStrLn "Processing done"
  router (RequestQueue requestQueue) newRouteMap

runRouter :: RequestQueue -> IO ()
runRouter requestQueue =
  router requestQueue (RouteMap Map.empty)
