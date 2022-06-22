module Raft.Types.RaftLog where

import Data.ByteString qualified as BS
import Data.Data
import Data.Sequence hiding (drop, zip)
import Data.Sequence qualified as S
import Data.Text qualified as T
import Util

type RaftCommand = T.Text

newtype Term = Term {number :: Int}
  deriving newtype (Show, FromJSON, ToJSON, Eq, Ord, Num)
  deriving (Generic)

data Entry = Entry
  { entryTerm :: Term,
    entryCommand :: T.Text
  }
  deriving (Show, Generic, FromJSON, ToJSON)

data RaftLog = RaftLog
  { entries :: S.Seq Entry,
    snapshotLen :: Int,
    snapshotTerm :: Term
  }
  deriving (Show, Generic, FromJSON, ToJSON)

makeLog = RaftLog S.empty 0 (Term 0)

logLength (RaftLog {..}) = S.length entries + snapshotLen

logTermLast l@(RaftLog {..}) = case S.viewr entries of
  (_ :> a) -> entryTerm a
  EmptyR -> snapshotTerm

data LogTermResult
  = Ok Term
  | InSnapshot (Int, Term) -- snapshotlen - term
  | OutOfBounds Int -- log length

logTermAt n l@(RaftLog {..})
  | n == snapshotLen - 1 = Ok $ snapshotTerm
  | n < snapshotLen = (InSnapshot (snapshotLen, snapshotTerm))
  | otherwise = case S.lookup (n - snapshotLen) entries of
      Nothing -> OutOfBounds (logLength l)
      (Just x) -> Ok $ entryTerm x

logEntriesAfter n l@(RaftLog {..}) =
  let (l, r) = S.splitAt (n - snapshotLen) entries
   in toList r

logAppend entry l@(RaftLog {..}) =
  let newSeq = entries |> entry
   in (l {entries = newSeq}, logLength l)

logAppendList index [] l@(RaftLog {..}) = l -- do nothing
logAppendList index (x : xs) l@(RaftLog {..})
  | index < snapshotLen = logAppendList snapshotLen (drop (snapshotLen - index) (x : xs)) l -- skip entries that are in snapshot
  | otherwise = case S.lookup (index - snapshotLen) entries of
      (Just a) | entryTerm a == entryTerm x -> logAppendList (index + 1) xs l
      _ ->
        let (left, _) = S.splitAt (index - snapshotLen) entries
         in l {entries = left >< (S.fromList (x : xs))}

logSearchLeftMostTerm term l@(RaftLog {..})
  | term == snapshotTerm = Just $ snapshotLen - 1
  | otherwise = (snapshotLen +) <$> (S.findIndexL ((== term) . entryTerm) entries)

logSearchRightMost term l@(RaftLog {..}) =
  case (snapshotLen +) <$> (S.findIndexR ((== term) . entryTerm) entries) of
    (Just x) -> (Just x)
    Nothing | term == snapshotTerm -> Just $ snapshotLen - 1
    _ -> Nothing

logEntriesBetween :: Int -> Int -> RaftLog -> [(Int, RaftCommand)]
logEntriesBetween start end l@(RaftLog {..})
  | end <= start = []
  | start < snapshotLen = []
  | otherwise =
      let startIndex = start - snapshotLen
       in zip [start ..] (fmap entryCommand $ toList $ S.take (end - start) $ S.drop startIndex entries)

logDropBefore :: Maybe Term -> Int -> RaftLog -> (Maybe RaftLog)
logDropBefore lastTerm newSnapLen l@(RaftLog {..})
  | newSnapLen <= snapshotLen = Nothing
  | newSnapLen > (logLength l) = fmap (\t -> RaftLog S.empty newSnapLen t) lastTerm
  | otherwise =
      let (left, r) = S.splitAt (newSnapLen - snapshotLen) entries
       in case S.viewr left of
            (_ :> a) -> Just $ RaftLog {snapshotLen = newSnapLen, snapshotTerm = entryTerm a, entries = r}
            EmptyR -> error "cannot happen"
