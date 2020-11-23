{-# LANGUAGE MultiParamTypeClasses #-}

module RouteMap where

import Data.List.Split (splitOn)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Queues.Publish (DeliveryQueue, PublishMessage (PublishMessage), topic)

newtype RouteMap = RouteMap (Map String [DeliveryQueue])

-- |
--  MQTT style topic matching.
matchTopic :: String -> String -> Bool
matchTopic subTopic pubTopic = matchTopic' (splitOn "/" subTopic) (splitOn "/" pubTopic)
  where
    matchTopic' :: [String] -> [String] -> Bool
    matchTopic' ("#" : _) _ = True -- Multi-level wildcard
    matchTopic' ("+" : ss) (_ : ps) = matchTopic' ss ps -- Single-level wildcard
    matchTopic' (s : ss) (p : ps) = s == p && matchTopic' ss ps -- Regular level match
    matchTopic' [] [] = True -- Fully matched
    matchTopic' _ _ = False -- otherwise: mismatch

findRoutes :: RouteMap -> PublishMessage -> [DeliveryQueue]
findRoutes (RouteMap routeMap) PublishMessage {topic = pubTopic} = do
  concat $ Map.elems $ Map.filterWithKey f routeMap
  where
    f :: String -> [DeliveryQueue] -> Bool
    f subTopic _ = matchTopic subTopic pubTopic
