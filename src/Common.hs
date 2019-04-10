{-# LANGUAGE DeriveGeneric          #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE InstanceSigs           #-}
{-# LANGUAGE MultiParamTypeClasses  #-}
{-# LANGUAGE NamedFieldPuns         #-}
{-# LANGUAGE ScopedTypeVariables    #-}
module Common where

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

import           Control.Monad.RWS.Lazy           (RWS, execRWS, get,
                                                   modify, put, tell)
import           Data.Foldable                    (for_)
import           Data.Traversable                 (for)

newtype Ticket
  = Ticket Int
  deriving (Show, Eq, Ord, Typeable, Generic)

instance Binary Ticket

type Command
  = String

type Proposal
  = (Ticket, Command)

class Message m c | m -> c where
  recipientOf :: m -> ProcessId
  msg :: m -> c

data ClientRequest
  = NewTicket Ticket
  | Propose Proposal
  | Execute
  deriving (Show, Typeable, Generic)

instance Binary ClientRequest

data ServerResponse
  = AllocatedTicket Ticket
  | HaveTicket Ticket
  | HaveProposal Proposal
  deriving (Show, Typeable, Generic)

instance Binary ServerResponse
