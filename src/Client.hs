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
import           Data.Foldable               (for_)
import           Data.Typeable               (Typeable)
import           GHC.Generics                (Generic)

import           Control.Lens                (makeLenses, (&), (+~),
                                              (^.), (^?))
import           Control.Lens.Extras         (is)
import           Control.Lens.TH             (makePrisms)
import           Control.Monad               (forever, when)
import           Control.Monad.RWS.Lazy      (RWS, execRWS, get, put,
                                              tell)

newtype IdleState
  = IdleState
      { _furthestKnownTicket :: Ticket
      }
    deriving (Show)
makeLenses ''IdleState

data Round1State
  = Round1State
      { _ticketToTry :: Ticket
      , _numOKs      :: Int
      }
    deriving (Show)
makeLenses ''Round1State

data Round2State
  = Round2State
  deriving (Show)
makeLenses ''Round2State

data ClientState
  = Idle IdleState
  | Round1 Round1State
  | Round2 Round2State
  deriving (Show)
makePrisms ''ClientState

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
      Idle $ IdleState { _furthestKnownTicket = Ticket 0 }
    ticker :: ProcessId -> Process ()
    ticker invokerPid =
      forever $ do
        liftIO $ threadDelay (10^6)
        send invokerPid Tick
    go :: ClientState -> Process ()
    go s = do
      (s', msgs) <-
        receiveWait
          [ match $ run handleServerResponse
          , match $ run handleTick
          ]
      say $ "client state: " ++ show s'
      sendMessages msgs
      go s'
      where
        run
          :: Typeable a
          => (a -> ClientAction ())
          -> a
          -> Process (ClientState, [ClientMessage])
        run handler msg =
          --say $ "handling msg type " ++ show (typeOf msg)
          return $ execRWS (handler msg) serverPids s

        handleServerResponse
          :: (ProcessId, ServerResponse)
          -> ClientAction ()
        handleServerResponse (sPid, HaveNewerTicket t) = do
          s <- get
          when (is _Round1 s) $
            put $ Idle $ IdleState t
        handleServerResponse (sPid, Round1OK ticket mProposal) = do
          s <- get
          for_ (s ^? _Round1) $ \round1S -> do
            let
              round1S' =
                round1S & numOKs +~ 1
            if haveRound1Majority round1S'
              then put $ Round2 Round2State
              else put $ Round1 round1S'

        haveRound1Majority :: Round1State -> Bool
        haveRound1Majority s =
          (s ^. numOKs) > floor (fromIntegral (length serverPids) / 2)

        handleTick :: Tick -> ClientAction ()
        handleTick _ = do
          s <- get
          for_ (s ^? _Idle) $ \idleS -> do
            let
              newTicket =
                idleS ^. furthestKnownTicket + 1
              numAcks =
                0
            put $ Round1 $ Round1State newTicket numAcks
            tell $ flip ClientMessage (AskForTicket newTicket) <$> serverPids
