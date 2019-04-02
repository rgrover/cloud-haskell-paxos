{-# LANGUAGE DeriveDataTypeable    #-}
{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE InstanceSigs          #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NamedFieldPuns        #-}
{-# LANGUAGE ScopedTypeVariables   #-}
module Client where

import           Common

import           Control.Concurrent               (threadDelay)
import           Control.Distributed.Process      (Process, ProcessId, ProcessMonitorNotification,
                                                   die, expect,
                                                   getSelfPid, match,
                                                   monitor,
                                                   receiveWait, say,
                                                   send, spawnLocal)
import           Control.Distributed.Process.Node
import           Control.Monad                    (forever, void)
import           Control.Monad.IO.Class           (liftIO)
import           Network.Transport.TCP            (createTransport, defaultTCPParameters)

import           Data.Binary                      (Binary)
import           Data.Typeable                    (Typeable)
import           GHC.Generics                     (Generic)

import           Control.Monad.Trans.RWS.Lazy     (RWS, execRWS, get,
                                                   modify, put, tell)
import           Data.Foldable                    (for_)
import           Data.Traversable                 (for)

data ClientState
  = ClientState
      { command :: String -- assumption: client repeats command
      , ticket  :: Ticket
      , pending :: Maybe ClientRequest
      }
      deriving (Show)

data ClientMessage
  = ClientMessage ProcessId ClientRequest
    deriving (Show, Generic, Typeable)

instance Message ClientMessage ClientRequest where
  recipientOf :: ClientMessage -> ProcessId
  recipientOf (ClientMessage p _) = p
  msg :: ClientMessage -> ClientRequest
  msg (ClientMessage _ r) = r

type ClientAction
  = RWS [ProcessId] [ClientMessage] ClientState
