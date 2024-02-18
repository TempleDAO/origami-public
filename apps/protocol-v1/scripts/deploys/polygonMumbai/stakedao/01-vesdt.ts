import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiVeSDTProxy__factory } from '../../../../typechain';
import {
    deployProxyAndMine,
    ensureExpectedEnvvars,
} from '../../helpers';
import { getDeployedContracts as stakeDaoDeployedContracts } from './contract-addresses';

async function main() {
    ensureExpectedEnvvars();
    const [owner] = await ethers.getSigners();
    const STAKEDAO_DEPLOYED_CONTRACTS = stakeDaoDeployedContracts();

    const factory = new OrigamiVeSDTProxy__factory(owner);
    await deployProxyAndMine(
        STAKEDAO_DEPLOYED_CONTRACTS.ORIGAMI.STAKEDAO.VE_SDT_PROXY,
        'veSDT Proxy', 'uups',
        [
            STAKEDAO_DEPLOYED_CONTRACTS.STAKEDAO.VE_SDT,
            STAKEDAO_DEPLOYED_CONTRACTS.STAKEDAO.SDT,
        ],
        factory, factory.deploy,
        await owner.getAddress(),
        STAKEDAO_DEPLOYED_CONTRACTS.STAKEDAO.VE_SDT_REWARDS_DISTRIBUTOR,
        STAKEDAO_DEPLOYED_CONTRACTS.STAKEDAO.VE_SDT_GAUGE_REWARDS_CLAIMER,
        STAKEDAO_DEPLOYED_CONTRACTS.STAKEDAO.SDT_LOCKER_GAUGE_CONTROLLER,
        STAKEDAO_DEPLOYED_CONTRACTS.STAKEDAO.SDT_STRATEGY_GAUGE_CONTROLLER,
        STAKEDAO_DEPLOYED_CONTRACTS.STAKEDAO.SNAPSHOT_DELEGATE_REGISTRY,
        STAKEDAO_DEPLOYED_CONTRACTS.STAKEDAO.VE_BOOST,
    );
}
        
// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
