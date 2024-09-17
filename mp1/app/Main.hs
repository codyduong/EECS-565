{-# LANGUAGE OverloadedStrings #-}

import qualified Data.Map.Strict as M
import qualified Data.Set as Set
import Data.Set (Set)
import Data.Char (isAlpha, toUpper, ord, chr)
import Control.Concurrent.Async
import Control.Concurrent
import Control.Concurrent.STM
import System.Environment (getArgs)
import System.Exit (exitFailure)
import Data.List (sortOn, transpose)
import Data.Ord (Down(..))
import Control.DeepSeq (deepseq, force)
import Text.Read (readMaybe)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Control.Monad (forM_, when, unless, replicateM)

main :: IO ()
main = do
  args <- getArgs
  case args of
    [encrypted, keyLengthStr, firstWordLengthStr] ->
      runCracker encrypted keyLengthStr firstWordLengthStr "dict.txt"
    [encrypted, keyLengthStr, firstWordLengthStr, dictPath] ->
      runCracker encrypted keyLengthStr firstWordLengthStr dictPath
    _ -> do
      putStrLn "Usage: VigenereCracker <encrypted_string> <key_length> <first_word_length> [dictionary_file]"
      exitFailure

runCracker :: String -> String -> String -> FilePath -> IO ()
runCracker encrypted keyLengthStr firstWordLengthStr dictPath = do
  case (readMaybe keyLengthStr :: Maybe Int, readMaybe firstWordLengthStr :: Maybe Int) of
    (Just keyLength, Just firstWordLength) -> do
      wordSet <- loadWordSet dictPath

      let uppercaseEncrypted = map toUpper encrypted

      let possibleShifts = getPossibleShifts uppercaseEncrypted keyLength 26

      workQueue <- newTQueueIO :: IO (TQueue String)
      resultsVar <- newMVar []
      activeWorkersVar <- newTVarIO 0

      atomically $ writeTQueue workQueue ""
      numCores <- getNumCapabilities

      let numWorkers = numCores * 1024 -- yeah that seems reasonable, lemme blow up my pc
      workers <- replicateM numWorkers (async $ workerThread workQueue activeWorkersVar resultsVar uppercaseEncrypted keyLength firstWordLength wordSet possibleShifts)
      mapM_ wait workers

      results <- readMVar resultsVar

      if null results
        then putStrLn "No valid keys found."
        else do
          putStrLn "Valid keys and decrypted messages:"
          forM_ results $ \(key, decryptedMessage) -> do
            putStrLn $ "Key: " ++ key
            putStrLn $ "Decrypted Message: " ++ decryptedMessage
            putStrLn "-----------------------------------"
    _ -> do
      putStrLn "Error: key_length, first_word_length, and top_n must be integers."
      exitFailure

-- simply multithreading wasn't enough, so implement N workers on a core to also run
workerThread :: TQueue String -> TVar Int -> MVar [(String, String)] -> String -> Int -> Int -> Set String -> [M.Map Char Int] -> IO ()
workerThread workQueue activeWorkersVar resultsVar encryptedText keyLength firstWordLength wordSet possibleShifts = do
  let loop = do
        maybePrefix <- atomically $ tryReadTQueue workQueue
        case maybePrefix of
          Just prefix -> do
            atomically $ modifyTVar' activeWorkersVar (+ 1)
            processPrefix prefix
            atomically $ modifyTVar' activeWorkersVar (\n -> n - 1)
            loop
          Nothing -> do
            activeWorkers <- readTVarIO activeWorkersVar
            Control.Monad.unless (activeWorkers == 0) loop
  loop
  where
    processPrefix prefix = do
      let position = length prefix
      if position == keyLength
        then do
          case decryptVigenerePrefix prefix encryptedText firstWordLength wordSet of
            Just _ -> do
              let decryptedMessage = decryptVigenere prefix encryptedText
              modifyMVar_ resultsVar (\results -> return ((prefix, decryptedMessage) : results))
            Nothing -> return ()
        else do
          let shiftMap = possibleShifts !! position
          let possibleLetters = M.keys shiftMap
          forM_ possibleLetters $ \c -> do
            let newPrefix = prefix ++ [c]
            when (validatePrefix newPrefix encryptedText firstWordLength wordSet) $ do
              atomically $ writeTQueue workQueue newPrefix

loadWordSet :: FilePath -> IO (Set String)
loadWordSet path = do
  content <- TIO.readFile path
  let wordList = map (map toUpper . T.unpack) $ T.lines content
  return $ Set.fromList wordList

getPossibleShifts :: String -> Int -> Int -> [M.Map Char Int]
getPossibleShifts text keyLength topN = map getTopNShifts frequencies
  where
    substrings = [[toUpper c | (c, idx) <- zip text [0 ..], idx `mod` keyLength == pos, isAlpha c] | pos <- [0 .. keyLength - 1]]

    frequencies = map (M.fromListWith (+) . flip zip (repeat 1)) substrings

    englishFreqOrder = "ETAOINSHRDLCUMWFGYPBVKJXQZ"

    -- yeah i dont know how this works tbh
    getTopNShifts freqMap =
      M.fromList $
        take topN $
          sortOn
            (Down . snd)
            [ (chr ((ord c - ord e + 26) `mod` 26 + ord 'A'), count)
              | (c, count) <- M.toList freqMap,
                e <- englishFreqOrder
            ]

decryptVigenerePrefix :: String -> String -> Int -> Set String -> Maybe String
decryptVigenerePrefix key text firstWordLength wordSet = go (cycle key) text firstWordLength ""
  where
    go _ _ 0 decrypted = if Set.member decrypted wordSet then Just decrypted else Nothing
    go (k : ks) (c : cs) remaining decrypted
      | isAlpha c =
          let decryptedChar = chr $ (ord (toUpper c) - ord k + 26) `mod` 26 + ord 'A'
              newDecrypted = decrypted ++ [decryptedChar]
           in if any (\w -> take (length newDecrypted) w == newDecrypted) (Set.toList wordSet)
                then go ks cs (remaining - 1) newDecrypted
                else Nothing
      | otherwise = go (k : ks) cs remaining decrypted -- skip non alpha
    go _ _ _ _ = Nothing

decryptVigenere :: String -> String -> String
decryptVigenere key = zipWith decryptChar (cycle key)
  where
    decryptChar k c
      | isAlpha c =
          let decryptedChar = chr $ (ord (toUpper c) - ord k + 26) `mod` 26 + ord 'A'
           in decryptedChar
      | otherwise = c -- keep non alpha

validatePrefix :: String -> String -> Int -> Set String -> Bool
validatePrefix keyPrefix encryptedText firstWordLength wordSet =
  case decryptVigenerePrefix keyPrefix encryptedText firstWordLength wordSet of
    Just _ -> True
    Nothing -> False