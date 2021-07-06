{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeFamilies #-}

module Queue where

import Control.Concurrent.STM (STM)

class Queue a b where
  recv :: a -> STM b
  send :: a -> b -> STM ()
