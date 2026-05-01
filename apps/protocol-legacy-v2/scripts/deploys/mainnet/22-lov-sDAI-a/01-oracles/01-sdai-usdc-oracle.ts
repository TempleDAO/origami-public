import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiErc4626Oracle__factory } from '../../../../../typechain';
import {
	deployAndMine,
	ensureExpectedEnvvars,
	ZERO_ADDRESS,
} from '../../../helpers';
import { connectToContracts1, getDeployedContracts1 } from '../../contract-addresses';

async function main() {
	ensureExpectedEnvvars();
	const [owner] = await ethers.getSigners();
	const ADDRS = await getDeployedContracts1(__dirname);
	const INSTANCES = connectToContracts1(owner, ADDRS);

	const factory = new OrigamiErc4626Oracle__factory(owner);
	await deployAndMine(
		'ORACLES.SDAI_USDC',
		factory,
		factory.deploy,
		{
			description: "sDAI/USDC",
			baseAssetAddress: ADDRS.EXTERNAL.MAKER_DAO.SDAI_TOKEN,
			baseAssetDecimals: await INSTANCES.EXTERNAL.MAKER_DAO.SDAI_TOKEN.decimals(),
			quoteAssetAddress: ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN,
			quoteAssetDecimals: await INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN.decimals(),
		},
		ZERO_ADDRESS,
	);
}

main()
	.then(() => process.exit(0))
	.catch(error => {
		console.error(error);
		process.exit(1);
	});