{-# LANGUAGE DeriveGeneric          #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE InstanceSigs           #-}
{-# LANGUAGE MultiParamTypeClasses  #-}
{-# LANGUAGE NamedFieldPuns         #-}
{-# LANGUAGE ScopedTypeVariables    #-}
{-# OPTIONS_GHC -fwarn-unused-imports #-}
module Common where

import           Control.Distributed.Process (Process, ProcessId,
                                              send)

import           Data.Binary                 (Binary)
import           Data.Typeable               (Typeable)
import           GHC.Generics                (Generic)

import           Data.Foldable               (traverse_)

newtype Ticket
  = Ticket Int
  deriving (Show, Eq, Ord, Typeable, Generic)

instance Binary Ticket

type Command
  = String

type Proposal
  = (Ticket, Command)

class (Binary c, Typeable c) => Message m c | m -> c where
  recipientOf :: m -> ProcessId
  contentOf   :: m -> c

sendMessages :: Message m c => [m] -> Process ()
sendMessages =
  traverse_ $ \m -> send (recipientOf m) (contentOf m)

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
