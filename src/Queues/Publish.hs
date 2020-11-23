{-# LANGUAGE MultiParamTypeClasses #-}

module Queues.Publish where

import Control.Concurrent.STM.TBQueue (TBQueue, readTBQueue, writeTBQueue)
import Queues.Queue

data PublishMessage = PublishMessage
  { topic :: String,
    message :: String
  }

newtype PublishQueue = PublishQueue (TBQueue PublishMessage)

newtype DeliveryQueue = DeliveryQueue (TBQueue PublishMessage) deriving Eq

instance Queue PublishQueue PublishMessage where
  recv (PublishQueue queue) = readTBQueue queue
  send (PublishQueue queue) = writeTBQueue queue

instance Queue DeliveryQueue PublishMessage where
  recv (DeliveryQueue queue) = readTBQueue queue
  send (DeliveryQueue queue) = writeTBQueue queue

--instance Eq DeliveryQueue where
--  a == b = a == b
