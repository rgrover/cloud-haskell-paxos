{-# LANGUAGE DeriveDataTypeable    #-}
{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE InstanceSigs          #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NamedFieldPuns        #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TemplateHaskell       #-}
{-# OPTIONS_GHC -fwarn-unused-imports #-}
module Server where

import           Common

import           Control.Distributed.Process (Process, ProcessId,
                                              match, receiveWait, say)

import           Data.Typeable               (Typeable)
import           GHC.Generics                (Generic)

import           Control.Lens                (makeLenses, use, (.=),
                                              (<>=))
import           Control.Monad               (when)
import           Control.Monad.RWS.Lazy      (RWS, execRWS, tell)

data ServerState
  = ServerState
      { _largestIssuedTicket :: Ticket
      , _proposal            :: Maybe Proposal
      , _executed            :: [String]
      }
      deriving (Show)
makeLenses ''ServerState

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
        handleClientRequest (requestor, AskForTicket reqTicket) = do
          newestTicket <- use largestIssuedTicket
          if newestTicket >= reqTicket
            then
              tell [ ServerMessage requestor $ HaveTicket newestTicket ]
            else do
              largestIssuedTicket .= reqTicket
              mP <- use proposal
              tell [ServerMessage requestor $ Round1OK reqTicket mP]

        handleClientRequest (requestor, Propose p@(ticket, command)) = do
          newestTicket <- use largestIssuedTicket
          when (ticket == newestTicket) $ do
            proposal .= Just p
            tell [ServerMessage requestor Round2Success]

        handleClientRequest (requestor, Execute t) = do
          newestTicket <- use largestIssuedTicket
          when (newestTicket == t) $ do
            Just (_, command) <- use proposal
            proposal .= Nothing
            executed <>= [command]

        run handler msg =
          return $ execRWS (handler msg) () s

      (s', msgs) <-
        receiveWait [ match $ run handleClientRequest ]
      say $ "server state: " ++ show s'
      --say $ "server msgs to send: " ++ show msgs

      sendMessages msgs
      go s'
