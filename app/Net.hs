module Net where

import Network.Simple.TCP (serve, HostPreference(Host, HostIPv4))
import Network.Socket (Socket, SockAddr)
import Control.Monad.IO.Class (MonadIO)
import qualified Control.Exception.Safe as Ex (catch, throw)
import Control.Monad (void)

serveTCP :: MonadIO m => m a
serveTCP = serve HostIPv4 "48350" handleAccept

handleAccept :: (Socket, SockAddr) -> IO ()
handleAccept (socket, addr) = do
  Ex.catch
    (void (acceptFork lsock k))
    Ex.throw
  putStrLn $ "TCP connection established from " ++ show addr
