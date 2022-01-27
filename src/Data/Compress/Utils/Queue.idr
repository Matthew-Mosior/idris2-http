module Data.Compress.Utils.Queue

import Data.Seq.Unsized
import Data.IORef
import Data.List
import System.Concurrency

data QueueEvent a = Msg a | Chan (Channel a)

export
data Queue a = Q Mutex (IORef (Seq (QueueEvent a)))

export
mk_queue : IO (Queue a)
mk_queue = pure $ Q !makeMutex !(newIORef empty)

||| receive a message, if empty, block until there is one
export
recv : Queue a -> IO a
recv (Q mutex ref) = do
  mutexAcquire mutex
  queue <- readIORef ref
  case viewl queue of
    Just (Msg message, rest) => do
      writeIORef ref rest
      mutexRelease mutex
      pure message
    _ => do
      chan <- makeChannel
      writeIORef ref (snoc queue (Chan chan))
      mutexRelease mutex
      channelGet chan

||| receive a message, if empty, returns nothing
export
recv' : Queue a -> IO (Maybe a)
recv' (Q mutex ref) = do
  mutexAcquire mutex
  queue <- readIORef ref
  case viewl queue of
    Just (Msg message, rest) => do
      writeIORef ref rest
      mutexRelease mutex
      pure $ Just message
    _ => do
      mutexRelease mutex
      pure Nothing

||| send a message to one of the receiver
export
signal : Queue a -> a -> IO ()
signal (Q mutex ref) msg = do
  mutexAcquire mutex
  queue <- readIORef ref
  case viewl queue of
    Just (Chan chan, rest) => do
      writeIORef ref rest
      mutexRelease mutex
      channelPut chan msg
    _ => do
      writeIORef ref (snoc queue (Msg msg))
      mutexRelease mutex

||| send a message to all the receivers
export
broadcast : Queue a -> a -> IO ()
broadcast (Q mutex ref) msg = do
  mutexAcquire mutex
  queue <- readIORef ref
  writeIORef ref empty
  mutexRelease mutex
  let channels = mapMaybe (\case Chan chan => Just chan; _ => Nothing) (toList queue)
  traverse_ (flip channelPut msg) channels
