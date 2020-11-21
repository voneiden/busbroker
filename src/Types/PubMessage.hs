module Types.PubMessage where

data PubMessage = PubMessage
  { topic :: String
  , message :: String
  }
