module KVTests.Test where

import Control.Monad.Reader
import Generic.Api
import Generic.Client
import Generic.Server
import Raft.App
import Raft.Impl
import Raft.Types.Raft
import UnliftIO
import Util
import Utilities.Environment
import Utilities.Network
 
runKVServer :: forall r m a. KVServerT r (TestEnvironmentT m) a -> (KVServerState r, Raft, TestEnvironment) -> m a
runKVServer a (server, raft, testEnv) = runNetwork (runRaftT (runKVServerT a (server)) raft) testEnv

runTestKVClerk action (state, testEnv) = runNetwork (runKVClientT action state) testEnv

makeKVServer :: (KVState state, MonadUnliftIO m) => [NodeId] -> TestNetwork -> NodeId -> m (KVServerState state, Raft, TestEnvironment)
makeKVServer servers network nodeId = do
  persister <- newTestPersister
  raft <- makeRaft servers
  server <- makeKVServerState
  let testEnv = TestEnvironment network persister nodeId
  runKVServer (start) (server, raft, testEnv)
  return (server, raft, testEnv)

makeKVClerk servers network nodeId = do
  persister <- newTestPersister
  let testEnv = TestEnvironment network persister nodeId
  clerk <- makeKVClientState servers
  return (clerk, testEnv)