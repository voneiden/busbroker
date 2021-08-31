module Mapper (runMapper) where

-- Mapper.hs does STM queue mapping between various outputs and inputs
-- In simulator terms, it maps data from stacktrix to the simulation data source and vice versa
import Control.Applicative ((<*))
import Control.Concurrent.STM (atomically, newTBQueue, writeTBQueue, readTBQueue)
import Data.Functor.Identity
import Data.Maybe (fromJust)
import Data.Tuple (swap)
import RouterTypes
import Text.Parsec (Parsec, (<|>))
import qualified Text.Parsec as Parsec
import Text.Parsec.Language
import qualified Text.Parsec.Token as Token
import Data.Char (chr)
import Data.Coerce (coerce)
import Control.Monad (forever)

-- sx/1/o/3 -> sim/i/SW_MAC
newtype SXId = SXId Integer deriving (Eq, Show)

newtype SXModuleId = SXModuleId Integer deriving (Eq, Show)

newtype SXRegister = SXRegister Integer deriving (Eq, Show)

--data SX = SX SXId SXModuleId SXRegister

--data Endpoint = SX SXId SXModuleId SXRegister | Sim String deriving (Eq, Show)
data Endpoint = InputTopic String | OutputTopic String deriving (Eq, Show)

newtype Input = Input String deriving (Eq, Show)
newtype Output = Output String deriving (Eq, Show)

data Mapping = Mapping Output Input deriving (Eq, Show)

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

endpoint :: Bool -> (String -> Endpoint)
endpoint input
  | input = InputTopic
  | otherwise = OutputTopic


chrs :: Integer -> String
chrs i = [chr $ fromIntegral i]

sxParser :: Bool -> Parsec String () String
sxParser input = do
  sxId <- symbol "x/" *> integer
  busId <- symbol (io input) *> integer
  reg <- symbol "/" *> integer <* symbol "/"
  return $ "sx/" ++ chrs sxId ++ io input ++ chrs busId ++ "/" ++ chrs reg ++ "/"


simParser :: Bool -> Parsec String () String
simParser input = do
  simIdentifier <- symbol "im" *> symbol (io input) *> identifier <* symbol "/"
  return $ "sim/" ++ io input ++ simIdentifier ++ "/"

inputParser :: Parsec String () Input
inputParser = do
  _ <- symbol "s"
  topic <- sxParser True <|> simParser True
  return $ Input topic


outputParser :: Parsec String () Output
outputParser = do
  _ <- symbol "s"
  topic <- sxParser False <|> simParser False
  return $ Output topic


myPairs :: Parsec String () [Mapping]
myPairs = Parsec.many1 $ do
  output <- whiteSpace *> outputParser
  input <- reservedOp "->" *> inputParser <* whiteSpace
  return $ Mapping output input

parseAll :: Parsec String () [Mapping]
parseAll = myPairs <* Parsec.eof

setup :: IO [Mapping]
setup = do
  routingData <- readFile "cfg/mapper.txt"
  case Parsec.parse parseAll "computer says no" routingData of
    Left er ->
      ioError $ userError $ "unable to parse mapper_routing.txt: " ++ show er
    Right mapping -> return mapping


relayResponse :: RequestQueue -> Response -> Mapping -> IO()
relayResponse (RequestQueue requestQueue) (PubResponse _ message) (Mapping _ (Input inputTopic)) = do
  atomically $ writeTBQueue requestQueue (PubRequest (Topic inputTopic) message)

runMapping :: RequestQueue -> ResponseQueue -> Mapping -> IO()
runMapping requestQueue (ResponseQueue responseQueue) mapping = do
  response <- atomically $ readTBQueue responseQueue
  relayResponse requestQueue response mapping

setupMapping :: RequestQueue -> Mapping -> IO ()
setupMapping requestQueue (Mapping (Output output) (Input input)) = do
  responseQueue <- atomically $ ResponseQueue <$> newTBQueue 1000
  _ <- atomically $ writeTBQueue (coerce requestQueue) (SubRequest (Topic input) responseQueue)
  forever $ runMapping requestQueue responseQueue (Mapping (Output output) (Input input))

--

runMapper :: RequestQueue -> IO ()
runMapper requestQueue = do
  mappings <- setup
  putStrLn $ "Loaded " ++ show (length mappings) ++ " mappings"
  mapM_ (setupMapping requestQueue) mappings
