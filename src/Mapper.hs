module Mapper (runMapper) where

-- Mapper.hs does STM queue mapping between various outputs and inputs
-- In simulator terms, it maps data from stacktrix to the simulation data source and vice versa
import Control.Applicative ((<*))
import Control.Concurrent.STM (atomically, newTBQueue, readTBQueue, writeTBQueue, TBQueue)
import Control.Monad (forever)
import Data.Char (chr)
import Data.Coerce (coerce)
import Data.Functor.Identity
import Data.Maybe (fromJust)
import Data.Tuple (swap)
import RouterTypes
import Text.Parsec (Parsec, (<|>))
import qualified Text.Parsec as Parsec
import Text.Parsec.Language
import qualified Text.Parsec.Token as Token
import Control.Concurrent (forkIO)
import Data.List.Split (splitOn)
import Network.Socket (SockAddr (SockAddrUnix))

-- TODO cacheable messages
-- Come up with a way that a client can request all matching cached inputs to be (re)deliveredy

-- sx/1/o/3 -> sim/i/SW_MAC
newtype SXId = SXId Integer deriving (Eq, Show)

newtype SXModuleId = SXModuleId Integer deriving (Eq, Show)

newtype SXRegister = SXRegister Integer deriving (Eq, Show)

newtype Output = Output String deriving (Eq, Show)

newtype Input = Input String deriving (Eq, Show)

newtype Endpoint = Endpoint String

--data Mapping = Mapping Output Input deriving (Eq, Show)
data Mapping = Mapping Output (Either Input (Topic -> Message -> [(Topic, Message)]))
-- This is just dum dum :(
--instance Show Endpoint where
--  show (SX id mod reg) = "sx/" ++ show id ++ "/" ++ output

lexerConfig :: GenLanguageDef String u Identity
lexerConfig =
  emptyDef
    { Token.reservedOpNames = ["->"],
      Token.commentLine = "#"
    }

lexer = Token.makeTokenParser lexerConfig :: Token.GenTokenParser String u Identity

reservedOp = Token.reservedOp lexer :: String -> Parsec.ParsecT String u Identity ()

symbol = Token.symbol lexer :: String -> Parsec.ParsecT String u Identity String

integer = Token.integer lexer :: Parsec.ParsecT String u Identity Integer

identifier = Token.identifier lexer :: Parsec.ParsecT String u Identity String

whiteSpace = Token.whiteSpace lexer :: Parsec.ParsecT String u Identity ()

io :: Bool -> [Char]
io input
  | input = "/i/"
  | otherwise = "/o/"

--endpoint :: Bool -> (String -> Endpoint)
--endpoint input
--  | input = InputTopic
--  | otherwise = OutputTopic

chrs :: Integer -> String
chrs i = [chr $ fromIntegral i]

sxParser :: Bool -> Parsec String () Endpoint
sxParser input = do
  sxId <- symbol "x/" *> integer
  busId <- symbol (io input) *> integer
  reg <- symbol "/" *> integer <* symbol "/"
  return $ Endpoint ("sx/" ++ show sxId ++ io input ++ show busId ++ "/" ++ show reg ++ "/")

simParser :: Bool -> Parsec String () Endpoint
simParser input = do
  simIdentifier <- symbol "im" *> symbol (io input) *> identifier <* symbol "/"
  return $ Endpoint ("sim" ++ io input ++ simIdentifier ++ "/")

inputParser :: Parsec String () Endpoint
inputParser = do
  sxParser True <|> simParser True

--return $ Input topic

outputParser :: Parsec String () Endpoint
outputParser = do
  sxParser False <|> simParser False

myPairs :: Parsec String () [Mapping]
myPairs = Parsec.many1 $ do
  output <- whiteSpace *> symbol "s" *> outputParser
  input <- reservedOp "->" *> symbol "s" *> inputParser <* whiteSpace
  return $ Mapping (coerce output) (Left (coerce input))

parseAll :: Parsec String () [Mapping]
parseAll = do
  myPairs <* Parsec.eof


setup :: IO [Mapping]
setup = do
  routingData <- readFile "cfg/mapper.txt"
  case Parsec.parse parseAll "computer says no" routingData of
    Left er ->
      ioError $ userError $ "unable to parse mapper_routing.txt: " ++ show er
    Right mapping -> return mapping

--mapRequest :: Output -> Either Input (Output -> Message -> [(Input, Message)]) -> Message -> [(Input, Message)]
--mapRequest _ (Left destinationTopic) message =
--  [(destinationTopic, message)]
--mapRequest sourceTopic (Right destinationFunc) message =
--  destinationFunc sourceTopic message

relayResponse :: RequestQueue -> Response -> Mapping -> IO ()
relayResponse (RequestQueue requestQueue) (PubResponse _ message _) (Mapping _ (Left (Input inputTopic))) = do
  atomically $ writeTBQueue requestQueue (PubRequest sockAddr (Topic (splitOn "/" inputTopic)) message)
relayResponse (RequestQueue requestQueue) (PubResponse topic message _) (Mapping _ (Right transformFunction)) = do
  mapM_ (\(inputTopic, inputMessage) -> atomically $ writeTBQueue requestQueue (PubRequest sockAddr inputTopic inputMessage)) inputs
    where
      inputs = transformFunction topic message 
relayResponse _ _ _ = return ()
  --atomically $ writeTBQueue requestQueue (PubRequest sockAddr (Topic (splitOn "/" inputTopic)) message)

runMapping :: RequestQueue -> ResponseQueue -> Mapping -> IO ()
runMapping requestQueue (ResponseQueue responseQueue) mapping = do
  response <- atomically $ readTBQueue responseQueue
  _ <- putStrLn $ "Mapper received: " ++ show response
  relayResponse requestQueue response mapping

sockAddr :: SockAddr
sockAddr = SockAddrUnix "Mapper"

setupMapping :: RequestQueue -> Mapping -> IO ()
setupMapping requestQueue (Mapping (Output output) (Left (Input input))) = do
  --putStrLn $ "Setup mapping " ++ show output ++ "->" ++show input
  responseQueue <- atomically $ ResponseQueue <$> newTBQueue 1000
  _ <- putStrLn $ "Mapper sub:" ++ show (Topic (splitOn "/" output))
  _ <- atomically $ writeTBQueue (coerce requestQueue) (SubRequest (Topic (splitOn "/" output)) (responseQueue, sockAddr))
  _ <- forkIO $ forever $ runMapping requestQueue responseQueue (Mapping (Output output) (Left (Input input)))
  return ()
setupMapping _ _ = return ()

respondPing :: RequestQueue -> ResponseQueue -> IO ()
respondPing pongQueue pingQueue = do
  ping <- atomically $ readTBQueue (coerce pingQueue)
  case ping of
    PingResponse t ->
      atomically $ writeTBQueue (coerce pongQueue) (PongRequest sockAddr t)
    _ ->
      return ()


runMapper :: RequestQueue -> IO ()
runMapper requestQueue = do
  pingResponseQueue <- atomically $ ResponseQueue <$> newTBQueue 1000
  _ <- atomically $ writeTBQueue (coerce requestQueue) (IdentifyRequest sockAddr (Just pingResponseQueue))
  _ <- forkIO $ forever $ respondPing requestQueue pingResponseQueue
  mappings <- setup
  putStrLn $ "Loaded " ++ show (length mappings) ++ " mappings"
  mapM_ (setupMapping requestQueue) mappings
