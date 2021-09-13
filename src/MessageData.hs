{-# LANGUAGE DeriveGeneric #-}
module MessageData where

import GHC.Generics (Generic)

data MessageData = MessageData
  { topic :: [String],
    message :: String,
    timestamp :: Integer,
    id :: Integer
  }
  deriving (Show, Generic)
