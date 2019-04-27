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
import           Data.Maybe                  (fromJust)
import           Data.Typeable               (Typeable)
import           GHC.Generics                (Generic)

import           Control.Lens                (makeLenses, (+=), (.=),
                                              (<+=), (<>~), (^.),
                                              (^?), (^?!))
import           Control.Lens.Combinators    (review, use)
import           Control.Lens.Extras         (is)
import           Control.Lens.Prism          (isn't)
import           Control.Lens.TH             (makePrisms)
import           Control.Monad               (forever, when)
import           Control.Monad.RWS.Lazy      (RWS, execRWS, get, tell)

newtype Round1State
  = Round1State
      { _mostRecentProposal :: MostRecentProposal
      }
  deriving (Show)
makeLenses ''Round1State

data Round2State
  = Round2State
      { _proposal               :: Proposal
      , _originalCommandPending :: Bool
      }
  deriving (Show)
makeLenses ''Round2State

data RoundState
  = Idle
  | Round1 Round1State
  | Round2 Round2State
  deriving (Show)
makePrisms ''RoundState

data ClientState
  = ClientState
      { _ticket     :: Ticket
      , _mCommand   :: Maybe Command
      , _numAcks    :: Int
      , _roundState :: RoundState
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

client :: [ProcessId] -> Int -> Process ()
client serverPids clientId = do
  getSelfPid >>= spawnLocal . ticker
  go initialClientState
  where
    initialClientState =
      ClientState
        (Ticket 0)
        Nothing    -- mCommand
        0          -- numAcks
        Idle       -- roundState
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
        handleServerResponse (sPid, HaveTicket serverTicket) = do
          s <- get
          when (isn't _Idle (s ^. roundState)) $ do
            ownTicket <- use ticket
            when (serverTicket >= ownTicket) $ do
              let
                nextTicket =
                  serverTicket + 1
              ticket     .= nextTicket
              numAcks    .= 0
              roundState .= Round1 (Round1State mempty)

              sendToAllServers $ AskForTicket nextTicket

        handleServerResponse (sPid, Round1OK ticketGranted mProposal) = do
          s <- get
          when (is _Round1 (s ^. roundState) &&
                ((s ^. ticket) == ticketGranted)) $ do
            numAcks += 1
            let
              round1S =
                fromJust $
                  (mostRecentProposal <>~ MostRecent mProposal) <$>
                    (s ^? (roundState . _Round1))
            reachedMajority <- haveMajority
            if not reachedMajority
              then roundState .= review _Round1 round1S
              else do
                Just myCommand <- use mCommand
                let
                  round2S =
                    case round1S ^. mostRecentProposal of
                      MostRecent Nothing ->
                        Round2State
                          (ticketGranted, myCommand) -- proposal
                          False -- own command pending
                      MostRecent (Just (_, previouslyChosenCommand)) ->
                        Round2State
                          (ticketGranted, previouslyChosenCommand)
                          True  -- own command pending
                numAcks .= 0
                roundState .= Round2 round2S
                sendToAllServers $ Propose (round2S ^. proposal)

        handleServerResponse (sPid, Round2Success) = do
          s <- get
          when (is _Round2 (s ^. roundState)) $ do
            numAcks += 1
            reachedMajority <- haveMajority
            when reachedMajority $ do
              sendToAllServers $ Execute (s ^. ticket)
              if s ^?! roundState . _Round2 . originalCommandPending
                then do
                  -- restart pending command
                  newTicket <- ticket <+= 1
                  numAcks .= 0
                  roundState .= (Round1 $ Round1State mempty)
                  sendToAllServers $ AskForTicket newTicket
                else do
                  mCommand   .= Nothing
                  numAcks    .= 0
                  roundState .= Idle

        haveMajority :: ClientAction Bool
        haveMajority =
          (> floor (fromIntegral (length serverPids) / 2)) <$>
            use numAcks

        handleTick :: Tick -> ClientAction ()
        handleTick _ = do
          s <- get
          when (is _Idle (s ^. roundState)) $ do
            Ticket t <- ticket <+= 1
            let
              command =
                "c" <> show clientId <> "." <> show t
            mCommand   .= Just command
            numAcks    .= 0
            roundState .= (Round1 $ Round1State mempty)
            sendToAllServers $ AskForTicket $ Ticket t
