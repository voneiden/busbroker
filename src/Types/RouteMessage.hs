module Types.RouteMessage where

data RouteMessage = RouteMessage
  { topic :: String
  , message :: String
  }
