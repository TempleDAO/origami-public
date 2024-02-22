import '@nomiclabs/hardhat-ethers';
import { ethers, network} from 'hardhat';
import { OrigamiTestnetMinter__factory, GMX_GMX__factory, OrigamiTestnetMinter, GMX_StakedGlp__factory } from '../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
  mine,
} from '../../helpers';
import { getDeployedContracts } from './contract-addresses';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const GMX_DEPLOYED_CONTRACTS = getDeployedContracts(network.name);

  const factory = new OrigamiTestnetMinter__factory(owner);
  const pairs = [
    {token: GMX_DEPLOYED_CONTRACTS.GMX.LIQUIDITY_POOL.WETH_TOKEN, amount: ethers.utils.parseEther("10"), mintType: 0,},
    {token: GMX_DEPLOYED_CONTRACTS.GMX.LIQUIDITY_POOL.BNB_TOKEN, amount: ethers.utils.parseEther("67"), mintType: 0,},
    // {token: GMX_DEPLOYED_CONTRACTS.GMX.LIQUIDITY_POOL.BTC_TOKEN, amount: ethers.utils.parseEther("0.4"), mintType: 0,},
    {token: GMX_DEPLOYED_CONTRACTS.GMX.LIQUIDITY_POOL.DAI_TOKEN, amount: ethers.utils.parseEther("20000"), mintType: 0,},
    {token: GMX_DEPLOYED_CONTRACTS.GMX.TOKENS.GMX_TOKEN, amount: ethers.utils.parseEther("500"), mintType: 0,},
    {token: GMX_DEPLOYED_CONTRACTS.GMX.STAKING.STAKED_GLP, amount: ethers.utils.parseEther("20000"), mintType: 1,},
  ];
  console.log([pairs, 86400]);
  const minter: OrigamiTestnetMinter = await deployAndMine(
    'GMX Testnet Minter', factory, factory.deploy,
    pairs,
    86400,
  );

  // Need to add it as a minter for GMX
  const gmx = GMX_GMX__factory.connect(GMX_DEPLOYED_CONTRACTS.GMX.TOKENS.GMX_TOKEN, owner);
  await mine(gmx.setMinter(minter.address, true));

  // Need to transfer any staked GLP (obtained when bootstrapping the liquidity pool)
  const sGlp = GMX_StakedGlp__factory.connect(GMX_DEPLOYED_CONTRACTS.GMX.STAKING.STAKED_GLP, owner);
  await mine(sGlp.transfer(minter.address, await sGlp.balanceOf(await owner.getAddress())));
}
        
// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });