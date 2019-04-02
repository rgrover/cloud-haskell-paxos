{-# LANGUAGE DeriveDataTypeable    #-}
{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE InstanceSigs          #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NamedFieldPuns        #-}
{-# LANGUAGE ScopedTypeVariables   #-}
module Server where

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
  recipientOf :: ServerMessage -> ProcessId
  recipientOf (ServerMessage p _) = p
  msg :: ServerMessage -> ServerResponse
  msg (ServerMessage _ r) = r

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
      for_ msgs $ \m -> send (recipientOf m) $ msg m
      go s'
