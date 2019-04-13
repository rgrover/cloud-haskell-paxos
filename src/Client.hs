{-# LANGUAGE DeriveDataTypeable    #-}
{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE InstanceSigs          #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NamedFieldPuns        #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TemplateHaskell       #-}
{-# OPTIONS_GHC -fwarn-unused-imports #-}
module Client where

import           Common

import           Control.Concurrent          (threadDelay)
import           Control.Distributed.Process (Process, ProcessId,
                                              getSelfPid, match,
                                              receiveWait, say, send,
                                              spawnLocal)
import           Control.Monad.IO.Class      (liftIO)

import           Data.Binary                 (Binary)
import           Data.Typeable               (Typeable, typeOf)
import           GHC.Generics                (Generic)

import           Control.Lens                (makeLenses, (+=))
import           Control.Monad               (forever)
import           Control.Monad.RWS.Lazy      (RWS, execRWS)

data ClientState
  = Idle
      { _furthestKnownTicket :: Ticket
      }
  | Round1
      { _newTicket  :: Ticket
      , _round1Acks :: Int
      }
      deriving (Show)
makeLenses ''ClientState

data ClientMessage
  = ClientMessage ProcessId ClientRequest
    deriving (Show, Generic, Typeable)

instance Message ClientMessage ClientRequest where
  recipientOf (ClientMessage p _) = p
  contentOf (ClientMessage _ r) = r

type ClientAction
  = RWS [ProcessId] [ClientMessage] ClientState

data Tick = Tick
  deriving (Generic, Typeable)

instance Binary Tick

client :: [ProcessId] -> Process ()
client serverPids = do
  getSelfPid >>= spawnLocal . ticker
  go initialClientState
  where
    initialClientState =
      Idle { _furthestKnownTicket = Ticket 1 }
    ticker :: ProcessId -> Process ()
    ticker destinationPid =
      forever $ do
        liftIO $ threadDelay (10^6)
        send destinationPid Tick
    go :: ClientState -> Process ()
    go s = do
      (s', msgs) <-
        receiveWait
          [ match $ run handleServerResponse
          , match $ run handleTick
          ]
      say $ show s'
      sendMessages msgs
      go s'
      where
        run
          :: Typeable a
          => (a -> ClientAction ())
          -> a
          -> Process (ClientState, [ClientMessage])
        run handler msg = do
          say $ "handling msg type " ++ show (typeOf msg)
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
handleTick :: Tick -> ClientAction ()
handleTick = const $
  --for_ serverPids $ \pid ->
    --send pid (self, NewTicket $ Ticket 1)
  return ()
