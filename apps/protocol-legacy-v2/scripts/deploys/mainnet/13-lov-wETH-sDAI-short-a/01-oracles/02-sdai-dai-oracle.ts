import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiErc4626Oracle__factory } from '../../../../../typechain';
import {
	deployAndMine,
	ensureExpectedEnvvars,
	ZERO_ADDRESS,
} from '../../../helpers';
import { connectToContracts, getDeployedContracts } from '../../contract-addresses';

async function main() {
	ensureExpectedEnvvars();
	const [owner] = await ethers.getSigners();
	const ADDRS = getDeployedContracts();
	const INSTANCES = connectToContracts(owner);

	const factory = new OrigamiErc4626Oracle__factory(owner);
	await deployAndMine(
		'ORACLES.SDAI_DAI',
		factory,
		factory.deploy,
		{
			description: "sDAI/DAI",
			baseAssetAddress: ADDRS.EXTERNAL.MAKER_DAO.SDAI_TOKEN,
			baseAssetDecimals: await INSTANCES.EXTERNAL.MAKER_DAO.SDAI_TOKEN.decimals(),
			quoteAssetAddress: ADDRS.EXTERNAL.MAKER_DAO.DAI_TOKEN,
			quoteAssetDecimals: await INSTANCES.EXTERNAL.MAKER_DAO.DAI_TOKEN.decimals(),
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