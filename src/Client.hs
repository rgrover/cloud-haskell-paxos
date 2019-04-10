{-# LANGUAGE DeriveDataTypeable    #-}
{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE InstanceSigs          #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NamedFieldPuns        #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TemplateHaskell       #-}
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

import           Control.Lens                     (makeLenses, (+=))
import           Control.Monad.RWS.Lazy           (RWS, execRWS, get,
                                                   modify, put, tell)
import           Data.Foldable                    (for_)
import           Data.Traversable                 (for)

data ClientState
  = Round1
      { _newTicket  :: Ticket
      , _round1Acks :: Int
      }
      deriving (Show)
makeLenses ''ClientState

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

runClient :: [ProcessId] -> ClientState -> Process ()
runClient serverPids = go
  where
    go s = do
      (s', _msgs) <- receiveWait [match $ run handleServerResponse]
      say $ show s'
      go s'
      where
        run
          :: (ServerResponse -> ClientAction ())
          -> ServerResponse
          -> Process (ClientState, [ClientMessage])
        run handler msg =
          return $ execRWS (handler msg) serverPids s

        handleServerResponse
          :: ServerResponse
          -> ClientAction ()
        handleServerResponse (HaveTicket t) =
          -- "main received: have-ticket: " ++ show t
          return ()
        handleServerResponse (AllocatedTicket t) = do
          round1Acks += 1
          --say $ "main received: allocated-ticket: " ++ show t
          return ()
        handleServerResponse (HaveProposal _) =
          -- "main received: have-proposal"
          return ()

