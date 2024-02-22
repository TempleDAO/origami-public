import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiLendingRewardsMinter__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';
import { getDeployedContracts } from '../contract-addresses';
import { DEFAULT_SETTINGS } from '../default-settings';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = getDeployedContracts();

  const factory = new OrigamiLendingRewardsMinter__factory(owner);
  await deployAndMine(
    'OV_USDC.SUPPLY.REWARDS_MINTER',
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.OV_USDC.TOKENS.O_USDC_TOKEN,
    ADDRS.OV_USDC.TOKENS.OV_USDC_TOKEN,
    ADDRS.OV_USDC.TOKENS.IUSDC_DEBT_TOKEN,
    DEFAULT_SETTINGS.OV_USDC.OUSDC_CARRY_OVER_BPS,
    ADDRS.CORE.FEE_COLLECTOR,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });