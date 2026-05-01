import '@nomiclabs/hardhat-ethers';
import { deployAndMine, mine, runAsyncMain, ZERO_ADDRESS } from '../../helpers';
import { getDeployContext } from '../deploy-context';
import { 
    OrigamiAutoStakingFactory,
    OrigamiAutoStakingToErc4626Deployer__factory,
} from '../../../../typechain';
import { OrigamiAutoStakingFactory__factory } from '../../../../typechain/factories/contracts/factories/staking';

const TEN_MINUTES = 600;

async function main() {
    const { owner, ADDRS } = await getDeployContext(__dirname);

    const vaultDeployerFactory = new OrigamiAutoStakingToErc4626Deployer__factory(owner);
    const vaultDeployer = await deployAndMine(
        'FACTORIES.INFRARED_AUTO_STAKING.VAULT_DEPLOYER',
        vaultDeployerFactory,
        vaultDeployerFactory.deploy,
        ADDRS.EXTERNAL.INFRARED.IBGT_TOKEN,
        ADDRS.VAULTS.ORIBGT.TOKEN,
    );

    // NB: No need for the swapper for now as Infrared only gives iBGT rewards
    // So the swapper deployer is set to the zero address
    {
        // const swapperDeployerFactory = new OrigamiSwapperWithCallbackDeployer__factory(owner);
        // const swapperDeployer = await deployAndMine(
        //     'FACTORIES.INFRARED_AUTO_STAKING.SWAPPER_DEPLOYER',
        //     swapperDeployerFactory,
        //     swapperDeployerFactory.deploy,
        // );
    }

    const factory = new OrigamiAutoStakingFactory__factory(owner);
    const generator = await deployAndMine(
        'FACTORIES.INFRARED_AUTO_STAKING.FACTORY',
        factory,
        factory.deploy,
        await owner.getAddress(),
        vaultDeployer.address,
        ADDRS.CORE.MULTISIG,
        TEN_MINUTES,
        ZERO_ADDRESS // swapperDeployer.address
    ) as OrigamiAutoStakingFactory;

    await mine(generator['proposeNewOwner(address)'](ADDRS.CORE.MULTISIG));
}

runAsyncMain(main);