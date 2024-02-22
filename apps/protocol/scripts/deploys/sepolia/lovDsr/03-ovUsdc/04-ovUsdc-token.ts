import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiInvestmentVault__factory } from '../../../../../typechain';
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

  const factory = new OrigamiInvestmentVault__factory(owner);
  await deployAndMine(
    'OV_USDC.TOKENS.OV_USDC_TOKEN',
    factory,
    factory.deploy,
    await owner.getAddress(),
    "Origami USDC Vault",
    "ovUSDC",
    ADDRS.OV_USDC.TOKENS.O_USDC_TOKEN,
    ADDRS.CORE.TOKEN_PRICES,
    DEFAULT_SETTINGS.OV_USDC.OUSDC_PERFORMANCE_FEE_BPS,
    DEFAULT_SETTINGS.OV_USDC.REWARDS_VEST_SECONDS,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });