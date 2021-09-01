module Stats where

import qualified Data.Map as Map
import Network.Socket (SockAddr)
import RouterTypes
import Util (epoch)

defaultRecord :: IO QueueStatistics
defaultRecord = do
  t <- epoch
  return $ QueueStatistics "Unidentified" 999 t 0 0

getRecord :: SockAddr -> QueueStatisticsMap -> IO QueueStatistics
getRecord addr (QueueStatisticsMap stats) = do
  case Map.lookup addr stats of
    Just record ->
      return record
    Nothing -> do
      defaultRecord

recordStatsOut :: SockAddr -> QueueStatisticsMap -> IO QueueStatisticsMap
recordStatsOut addr (QueueStatisticsMap stats) = do
  record <- getRecord addr (QueueStatisticsMap stats)
  return $ QueueStatisticsMap $ Map.insert addr record {queueMessagesOut = queueMessagesOut record + 1} stats

recordStatsIn :: SockAddr -> QueueStatisticsMap -> IO QueueStatisticsMap
recordStatsIn addr (QueueStatisticsMap stats) = do
  record <- getRecord addr (QueueStatisticsMap stats)
  return $ QueueStatisticsMap $ Map.insert addr record {queueMessagesIn = queueMessagesIn record + 1} stats

recordStatsName :: SockAddr -> QueueStatisticsMap -> String -> IO QueueStatisticsMap
recordStatsName addr (QueueStatisticsMap stats) name = do
  record <- getRecord addr (QueueStatisticsMap stats)
  return $ QueueStatisticsMap $ Map.insert addr record {queueName = name} stats

recordStatsPing :: SockAddr -> QueueStatisticsMap -> Integer -> IO QueueStatisticsMap
recordStatsPing addr (QueueStatisticsMap stats) pong = do
  now <- epoch 
  record <- getRecord addr (QueueStatisticsMap stats)
  return $ QueueStatisticsMap $ Map.insert addr record {queuePing = now - pong} stats
