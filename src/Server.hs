{-# LANGUAGE DeriveDataTypeable    #-}
{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE InstanceSigs          #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NamedFieldPuns        #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# OPTIONS_GHC -fwarn-unused-imports #-}
module Server where

import           Common

import           Control.Distributed.Process (Process, ProcessId,
                                              match, receiveWait, say)

import           Data.Typeable               (Typeable)
import           GHC.Generics                (Generic)

import           Control.Monad.RWS.Lazy      (RWS, execRWS, get, put,
                                              tell)

data ServerState
  = ServerState
      { maxTicket :: Ticket
      , proposal  :: Maybe Proposal
      , executed  :: [String]
      }
      deriving (Show)

data ServerMessage
  = ServerMessage ProcessId ServerResponse
    deriving (Show, Generic, Typeable)

instance Message ServerMessage ServerResponse where
  recipientOf (ServerMessage p _) = p
  contentOf (ServerMessage _ r) = r

type ServerAction
  = RWS () [ServerMessage] ServerState

server :: Process ()
server =
  go $ ServerState (Ticket 0) Nothing []
  where
    go :: ServerState -> Process ()
    go s = do
      let
        handleClientRequest
          :: (ProcessId, ClientRequest)
          -> ServerAction ()
        handleClientRequest (requestor, NewTicket t) = do
          s <- get
          let
            ownTicket =
              maxTicket s
          if ownTicket >= t
            then
              tell [ServerMessage requestor $ HaveTicket ownTicket]
            else do
              put $ s {maxTicket = t}
              tell [ServerMessage requestor $ AllocatedTicket t]
        run handler msg =
          return $ execRWS (handler msg) () s

      (s', msgs) <-
        receiveWait [ match $ run handleClientRequest ]
      say $ "state: " ++ show s'
      sendMessages msgs
      go s'
