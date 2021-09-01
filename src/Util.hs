module Util (epoch) where

import Data.Time.Clock.POSIX (getPOSIXTime)

epoch :: IO Integer
epoch = round . (* 1000) <$> getPOSIXTime
