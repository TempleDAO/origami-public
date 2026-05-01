import '@nomiclabs/hardhat-ethers';
import { ethers, network } from 'hardhat';
import {
  impersonateAndFund2,
  mine,
  runAsyncMain,
} from '../../../helpers';
import { getDeployContext } from '../../deploy-context';
import { CoolerLtvOracle__factory, CoolerTreasuryBorrower__factory, Kernel__factory, MonoCooler__factory, RolesAdmin__factory } from '../../../../../typechain';
import { formatBytes32String } from 'ethers/lib/utils';
import { BigNumber } from 'ethers';

const OLYMPUS_CONTRACTS = {
  Kernel: "0x2286d7f9639e8158FaD1169e76d1FbC38247f54b",
  CoolerV2: "0xdb591Ea2e5Db886dA872654D58f6cc584b68e7cC",
  CoolerV2LtvOracle: "0x9ee9f0c2e91E4f6B195B988a9e6e19efcf91e8dc",
  CoolerV2TreasuryBorrower: "0xD58d7406E9CE34c90cf849Fc3eed3764EB3779B0",
  DelegateEscrowFactory: "0xC84157C2306238C9330fEa14774a82A53a127A59",
  OlympusGovDelegation: "0xD3204Ae00d6599Ba6e182c6D640A79d76CdAad74",
  RolesAdmin: "0xb216d714d91eeC4F7120a732c11428857C659eC8",
};

// Note: This is only required in the period of time prior to Olympus snapshot enabling MonoCooler
// network == localhost only

async function main() {
  if (network.name != 'localhost') return;
  
  const {owner, ADDRS} = await getDeployContext(__dirname);
  
  const kernel = Kernel__factory.connect(OLYMPUS_CONTRACTS.Kernel, owner);
  const executor = await impersonateAndFund2(await kernel.executor());

  const rolesAdmin = RolesAdmin__factory.connect(OLYMPUS_CONTRACTS.RolesAdmin, owner);
  const admin = await impersonateAndFund2(await rolesAdmin.admin());
  await mine(rolesAdmin.connect(admin).grantRole(
    formatBytes32String("treasuryborrower_cooler"),
    OLYMPUS_CONTRACTS.CoolerV2
  ));
  await mine(rolesAdmin.connect(admin).grantRole(
    formatBytes32String("admin"),
    owner.getAddress()
  ));

  await mine(kernel.connect(executor).executeAction(0 /*InstallModule*/, OLYMPUS_CONTRACTS.OlympusGovDelegation));
  await mine(kernel.connect(executor).executeAction(2 /*ActivatePolicy*/, OLYMPUS_CONTRACTS.CoolerV2));
  await mine(kernel.connect(executor).executeAction(2 /*ActivatePolicy*/, OLYMPUS_CONTRACTS.CoolerV2LtvOracle));
  await mine(kernel.connect(executor).executeAction(2 /*ActivatePolicy*/, OLYMPUS_CONTRACTS.CoolerV2TreasuryBorrower));

  const ltvOracle = CoolerLtvOracle__factory.connect(OLYMPUS_CONTRACTS.CoolerV2LtvOracle, owner);
  await mine(ltvOracle.setOriginationLtvAt(
    ethers.utils.parseEther("2991.2564"),
    1778803200 // 15th May 2026
  ));

  const treasuryBorrower = CoolerTreasuryBorrower__factory.connect(OLYMPUS_CONTRACTS.CoolerV2TreasuryBorrower, owner);
  await mine(treasuryBorrower.enable(formatBytes32String("")));

  const maxUint32 = BigNumber.from(2).pow(BigNumber.from(32)).sub(1);
  const monoCooler = MonoCooler__factory.connect(OLYMPUS_CONTRACTS.CoolerV2, owner);
  await mine(monoCooler.setMaxDelegateAddresses(ADDRS.VAULTS.hOHM.MANAGER, maxUint32));
}

runAsyncMain(main);
