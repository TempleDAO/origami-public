import '@nomiclabs/hardhat-ethers';
import { deployAndMine, mine, runAsyncMain } from '../../../helpers';
import { getDeployContext } from '../../deploy-context';
import { 
    OrigamiDelegated4626VaultDeployer__factory,
    OrigamiInfraredAutoCompounderFactory,
    OrigamiInfraredAutoCompounderFactory__factory,
    OrigamiInfraredVaultManagerDeployer__factory,
    OrigamiSwapperWithLiquidityManagementDeployer__factory
} from '../../../../../typechain';

async function main() {
    const { owner, ADDRS } = await getDeployContext(__dirname);

    const vaultDeployerFactory = new OrigamiDelegated4626VaultDeployer__factory(owner);
    const vaultDeployer = await deployAndMine(
        'FACTORIES.INFRARED_AUTO_COMPOUNDER.VAULT_DEPLOYER',
        vaultDeployerFactory,
        vaultDeployerFactory.deploy,
    );

    const managerDeployerFactory = new OrigamiInfraredVaultManagerDeployer__factory(owner);
    const managerDeployer = await deployAndMine(
        'FACTORIES.INFRARED_AUTO_COMPOUNDER.MANAGER_DEPLOYER',
        managerDeployerFactory,
        managerDeployerFactory.deploy,
    );

    const swapperDeployerFactory = new OrigamiSwapperWithLiquidityManagementDeployer__factory(owner);
    const swapperDeployer = await deployAndMine(
        'FACTORIES.INFRARED_AUTO_COMPOUNDER.SWAPPER_DEPLOYER',
        swapperDeployerFactory,
        swapperDeployerFactory.deploy,
    );

    const factory = new OrigamiInfraredAutoCompounderFactory__factory(owner);
    const generator = await deployAndMine(
        'FACTORIES.INFRARED_AUTO_COMPOUNDER.FACTORY',
        factory,
        factory.deploy,
        await owner.getAddress(),
        ADDRS.CORE.TOKEN_PRICES.V4,
        ADDRS.CORE.MULTISIG,
        vaultDeployer.address,
        managerDeployer.address,
        swapperDeployer.address
    ) as OrigamiInfraredAutoCompounderFactory;

    await mine(generator.proposeNewOwner(ADDRS.CORE.MULTISIG));
}

runAsyncMain(main);
