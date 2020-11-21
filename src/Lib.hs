module Lib
  ( someFunc,
  )
where

import qualified Control.Concurrent as Concurrent (forkIO, threadDelay)
import Data.ByteString.UTF8 as BSU
import qualified Data.ByteString as BS
import Network.Multicast (multicastReceiver, multicastSender)
import qualified Network.Socket as Socket
import qualified Network.Socket.ByteString as Socket (recvFrom, sendTo)
import qualified Data.ByteString.Builder as Builder (toLazyByteString, byteStringHex)
import qualified Data.ByteString.Char8 as C8 (pack)

toIP :: (Integral a) => [a] -> [Int]
toIP = map fromIntegral



serveSlam :: IO ()
serveSlam = do
  sock <- multicastReceiver "224.0.0.64" 9999
  (mac, _) <- Socket.recvFrom sock 5
  let foo = Builder.toLazyByteString . Builder.byteStringHex $ mac
  print "RECV"
  print foo
  print $ toIP (BS.unpack mac)
  --print (msg, addr)
  Socket.close sock

someFunc :: IO ()
someFunc = do
  --addressInfo <- getAddrInfo Nothing (Just "127.0.0.1") (Just "7000")
  --let serverAddress = head addressInfo
  --sock <- socket (addrFamily serverAddress) Datagram defaultProtocol
  --bind sock (addrAddress serverAddress)

  _ <- Concurrent.forkIO serveSlam
  Concurrent.threadDelay 1000000 -- wait one second
  (sock, addr) <- multicastSender "224.0.0.64" 9999
  _ <- Socket.sendTo sock (C8.pack "\xde\xad\xbe\xef\x01") addr
  Socket.close sock
  Concurrent.threadDelay 1000000 -- wait one second
  Prelude.putStrLn "Hello World"

--224.0.0.0
