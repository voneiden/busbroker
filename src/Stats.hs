module Stats where

import qualified Data.Map.Strict as Map
import Network.Socket (SockAddr)
import RouterTypes
import Util (epoch)
import Data.Coerce (coerce)

defaultRecord :: SockAddr -> IO QueueStatistics
defaultRecord addr = do
  t <- epoch
  return $ QueueStatistics addr 999 t 0 0

getRecord :: SockAddr -> QueueStatisticsMap -> IO QueueStatistics
getRecord addr (QueueStatisticsMap stats) = do
  case Map.lookup addr stats of
    Just record ->
      return record
    Nothing -> do
      defaultRecord addr

recordIdentify :: SockAddr -> QueueStatisticsMap -> IO QueueStatisticsMap
recordIdentify addr stats = do
  record <- getRecord addr stats
  return $ coerce $ Map.insert addr record $ coerce stats

recordStatsOut :: SockAddr -> QueueStatisticsMap -> IO QueueStatisticsMap
recordStatsOut addr stats = do
  record <- getRecord addr stats
  return $ coerce $ Map.insert addr record {messagesOut = messagesOut record + 1} $ coerce stats

recordStatsIn :: SockAddr -> QueueStatisticsMap -> IO QueueStatisticsMap
recordStatsIn addr stats = do
  record <- getRecord addr stats
  return $ coerce $ Map.insert addr record {messagesIn = messagesIn record + 1} $ coerce stats

recordStatsPing :: SockAddr -> QueueStatisticsMap -> Integer -> IO QueueStatisticsMap
recordStatsPing addr stats pong = do
  now <- epoch
  record <- getRecord addr stats
  return $ coerce $ Map.insert addr record {ping = now - pong} $ coerce stats

deleteStats :: SockAddr -> QueueStatisticsMap -> QueueStatisticsMap
deleteStats addr stats = QueueStatisticsMap $ Map.delete addr $ coerce stats
