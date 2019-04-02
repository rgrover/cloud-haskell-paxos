{-# LANGUAGE InstanceSigs          #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NamedFieldPuns        #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TupleSections         #-}
module Main where

import           Client
import           Common
import           Server

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

main :: IO ()
main = do
  let
    host =
      "127.0.0.1"
    port =
      "10501"
  Right t <-
    createTransport host port (host,) defaultTCPParameters
  node <- newLocalNode t initRemoteTable
  void $ runProcess node $ do
    self       <- getSelfPid
    serverPids <- for [1..3] $ const $ spawnLocal server

    for_ serverPids monitor
    for_ serverPids $ \pid ->
      send pid (self, NewTicket $ Ticket 1)

    let
      --run handler msg =
        --return $ execRWS (handler msg) () s
      logServerResponse :: ServerResponse -> Process ()
      logServerResponse (HaveTicket t) =
        say $ "main received: have-ticket: " ++ show t
      logServerResponse (AllocatedTicket t) =
        say $ "main received: allocated-ticket: " ++ show t
      logServerResponse (HaveProposal _) =
        say "main received: have-proposal"
    forever $
      receiveWait [match logServerResponse]

{-
 -data ClientState
 -  = ClientState
 -      { command :: String -- assumption: client repeats command
 -      , ticket  :: Ticket
 -      , pending :: Maybe ClientRequest
 -      }
 -      deriving (Show)
 -}
