{-# LANGUAGE DeriveGeneric              #-}
{-# LANGUAGE FunctionalDependencies     #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE InstanceSigs               #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE NamedFieldPuns             #-}
{-# LANGUAGE ScopedTypeVariables        #-}
{-# OPTIONS_GHC -fwarn-unused-imports #-}
module Common where

import           Control.Distributed.Process (Process, ProcessId,
                                              getSelfPid, send)

import           Data.Binary                 (Binary)
import           Data.Typeable               (Typeable)
import           GHC.Generics                (Generic)

import           Data.Foldable               (for_)

newtype Ticket
  = Ticket Int
  deriving (Show, Eq, Ord, Num, Typeable, Generic)

instance Binary Ticket

type Command
  = String

type Proposal
  = (Ticket, Command)

class (Binary c, Typeable c) => Message m c | m -> c where
  recipientOf :: m -> ProcessId
  contentOf   :: m -> c

sendMessages :: Message m c => [m] -> Process ()
sendMessages ms = do
  selfPid <- getSelfPid
  for_ ms $ \m -> send (recipientOf m) (selfPid, contentOf m)

data ClientRequest
  = AskForTicket Ticket
  | Propose Proposal
  | Execute
  deriving (Show, Typeable, Generic)

instance Binary ClientRequest

data ServerResponse
  = Round1OK Ticket (Maybe Proposal)
  | HaveTicket Ticket
  | Round2Success
  deriving (Show, Typeable, Generic)

instance Binary ServerResponse

newtype MostRecentProposal
  = MostRecent (Maybe Proposal)
  deriving (Show)

instance Semigroup MostRecentProposal where
  (MostRecent Nothing) <> r = r
  r <> (MostRecent Nothing) = r
  r1@(MostRecent (Just (t1, _))) <> r2@(MostRecent (Just (t2, _))) =
    if t1 >= t2 then r1 else r2

instance Monoid MostRecentProposal where
  mempty = MostRecent Nothing
