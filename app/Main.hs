module Main where

import Control.Concurrent.STM (atomically, newTBQueue)
import Net (runTCPServer)
import Router (runRouter)
import Mapper (runMapper)
import Web (runScotty)
import RouterTypes (RequestQueue (RequestQueue))
import Control.Concurrent (forkIO)

main :: IO ()
main = do
  requestQueue <- atomically $ RequestQueue <$> newTBQueue 1000
  _ <- forkIO $ runRouter requestQueue
  _ <- forkIO $ runMapper requestQueue
  _ <- forkIO runScotty
  _ <- runTCPServer Nothing "42069" requestQueue
  putStrLn "Done, good night."
  return ()
