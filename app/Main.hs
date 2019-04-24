{-# LANGUAGE InstanceSigs          #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NamedFieldPuns        #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TupleSections         #-}
{-# OPTIONS_GHC -fwarn-unused-imports #-}
module Main where

import           Client
import           Server

import           Control.Distributed.Process      (Process, ProcessMonitorNotification,
                                                   getSelfPid, match,
                                                   monitor,
                                                   receiveWait, say,
                                                   spawnLocal)

import           Control.Distributed.Process.Node
import           Control.Monad                    (forever, void)
import           Network.Transport.TCP            (createTransport, defaultTCPParameters)

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

    -- start servers
    serverPids <- for [1..4] $ const $ spawnLocal server
    for_ serverPids monitor

    -- start client
    clientPid <- spawnLocal (client serverPids)
    void $ monitor clientPid

    -- reap monitor notifications
    let
      handler :: ProcessMonitorNotification -> Process ()
      handler n = say $ "received monitor notification: " ++ show n
    forever $
      receiveWait [match handler]
