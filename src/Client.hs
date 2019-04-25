{-# LANGUAGE DeriveDataTypeable    #-}
{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE InstanceSigs          #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NamedFieldPuns        #-}
{-# LANGUAGE Rank2Types            #-}
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
import           Data.Maybe                  (fromMaybe)
import           Data.Typeable               (Typeable)
import           GHC.Generics                (Generic)

import           Control.Lens                (Lens', makeLenses, (&),
                                              (+~), (.~), (<>~), (^.),
                                              (^?))
import           Control.Lens.Combinators    (_2)
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
      { _round1Command      :: Command
      , _ticketBeingAsked   :: Ticket
      , _numOKs             :: Int
      , _mostRecentProposal :: MostRecentProposal
      }
    deriving (Show)
makeLenses ''Round1State

data Round2State
  = Round2State
      { _ticketOwned    :: Ticket
      , _round2Proposal :: Proposal
      , _round2OKs      :: Int
      , _pendingCommand :: Maybe Command
      }
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

client :: [ProcessId] -> Int -> Process ()
client serverPids clientId = do
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
      --say $ "client msgs to send: " ++ show msgs
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

        sendToAllServers :: ClientRequest -> ClientAction ()
        sendToAllServers m = tell $ flip ClientMessage m <$> serverPids

        handleServerResponse
          :: (ProcessId, ServerResponse)
          -> ClientAction ()
        handleServerResponse (sPid, HaveTicket newerT) = do
          s <- get
          let
            newerT' = newerT + 1
          case s of
            Round1 round1S ->
              let
                round1S' =
                  round1S &
                    (ticketBeingAsked .~ newerT') .
                    (numOKs .~ 0)
              in put $ Round1 round1S'
            Round2 round2S ->
              let
                pendingC =
                  round2S ^. pendingCommand
                command =
                  fromMaybe (round2S ^. round2Proposal . _2) pendingC
              in put $ Round1 $ Round1State command newerT' 0 mempty
          sendToAllServers $ AskForTicket newerT'

        handleServerResponse (sPid, Round1OK ticketGranted mProposal) = do
          s <- get
          for_ (s ^? _Round1) $ \round1S ->
            when (round1S ^. ticketBeingAsked == ticketGranted) $ do
              let
                round1S' =
                  round1S &
                    (numOKs +~ 1) .
                    (mostRecentProposal <>~ MostRecent mProposal)
              if not $ haveMajority round1S' numOKs
                then put $ Round1 round1S'
                else do
                  let
                    ticket =
                      round1S ^. ticketBeingAsked
                    myCommand =
                      round1S' ^. round1Command
                    (proposal, pending) =
                      case round1S' ^. mostRecentProposal of
                        MostRecent Nothing ->
                          ((ticket, myCommand), Nothing)
                        MostRecent (Just (_, previouslyChosenCommand)) ->
                          ((ticket, previouslyChosenCommand), Just myCommand)
                    nOKs = 0
                  put $ Round2 $ Round2State ticket proposal nOKs pending
                  sendToAllServers $ Propose proposal

        handleServerResponse (sPid, Round2Success) = do
          s <- get
          for_ (s ^? _Round2) $ \round2S -> do
            let
              round2S' =
                round2S & round2OKs +~ 1
            if not (haveMajority round2S' round2OKs)
              then
                put $ Round2 round2S'
              else do
                let
                  t =
                    round2S ^. ticketOwned
                sendToAllServers $ Execute t
                case round2S ^. pendingCommand of
                  Nothing ->
                    put $ Idle $ IdleState t
                  Just command -> do
                    -- restart pending command
                    let
                      newTicket =
                        t + 1
                    put $ Round1 $
                      Round1State command newTicket 0 mempty
                    sendToAllServers $ AskForTicket newTicket

        haveMajority :: s -> Lens' s Int -> Bool
        haveMajority s l =
          (s ^. l) > floor (fromIntegral (length serverPids) / 2)

        handleTick :: Tick -> ClientAction ()
        handleTick _ = do
          s <- get
          for_ (s ^? _Idle) $ \idleS -> do
            let
              newTicket@(Ticket t) =
                idleS ^. furthestKnownTicket + 1
              numAcks =
                0
              command =
                "c" <> show clientId <> "." <> show t
            put $ Round1 $ Round1State command newTicket numAcks mempty
            sendToAllServers $ AskForTicket newTicket
