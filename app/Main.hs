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

import           Control.Monad.RWS.Lazy           (execRWS, get,
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
      initialClientState =
        Round1
          (Ticket 1) -- proposal
          0 -- acks

    runClient serverPids initialClientState
