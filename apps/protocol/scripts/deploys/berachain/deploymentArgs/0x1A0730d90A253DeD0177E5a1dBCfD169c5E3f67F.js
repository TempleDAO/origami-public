// berachain: VAULTS.INFRARED_AUTO_STAKING_OHM_HONEY_A.VAULT=0x1A0730d90A253DeD0177E5a1dBCfD169c5E3f67F
// yarn hardhat verify --network berachain 0x1A0730d90A253DeD0177E5a1dBCfD169c5E3f67F --constructor-args scripts/deploys/berachain/deploymentArgs/0x1A0730d90A253DeD0177E5a1dBCfD169c5E3f67F.js
module.exports = [
  {
    initialOwner: '0xc3d19ac9b79a8d89272a7ef88ddc1786fe36d747', // The factory
    stakingToken: '0x98bDEEde9A45C28d229285d9d6e9139e9F505391', // KODI OHM/HONEY
    primaryRewardToken: '0x69f1E971257419B1E9C405A553f252c64A29A30a', // oriBGT
    rewardsVault: '0xa57Cb177Beebc35A1A26A286951a306d9B752524',
    primaryPerformanceFeeBps: 100,
    feeCollector: '0x781b4c57100738095222bd92d37b07ed034ab696', // CORE.MULTISIG
    rewardsDuration: 600, // 10 minutes
    swapper: '0x0000000000000000000000000000000000000000', // Unused
  },
  '0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b', // iBGT
];
