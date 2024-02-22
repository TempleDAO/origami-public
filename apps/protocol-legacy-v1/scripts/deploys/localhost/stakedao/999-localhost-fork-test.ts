import { Contract, Signer } from 'ethers';
import { ethers } from 'hardhat';
import { impersonateSigner, mineForwardSeconds } from '../../../../test/helpers';
import { 
    OrigamiVeSDTProxy, OrigamiVeSDTProxy__factory,
    TimelockController, TimelockController__factory,
    IStakeDao_VeSDT, IStakeDao_VeSDT__factory,
    IERC20, IERC20__factory, 
    IStakeDao_GaugeController, IStakeDao_GaugeController__factory,
    IStakeDao_WalletWhitelist, IStakeDao_WalletWhitelist__factory,
} from '../../../../typechain';
import {
    blockTimestamp,
    ensureExpectedEnvvars,
    mine,
} from '../../helpers';
import { StakeDaoDeployedContracts, getDeployedContracts as stakeDaoDeployedContracts } from '../../mainnet/stakedao/contract-addresses';
import { GovernanceDeployedContracts, getDeployedContracts as govDeployedContracts } from '../../mainnet/governance/contract-addresses';

const mainnetAddresses = {
    sdtWhaleAddr: '0xAced00E50cb81377495ea40A1A44005fe6d2482d',

    // https://lockers.stakedao.org/lockers/crv
    sdCRV_gauge: '0x7f50786A0b15723D741727882ee99a0BF34e3466',

    // https://lockers.stakedao.org/lockers/angle
    sdANGLE_gauge: '0xE55843a90672f7d8218285e51EE8fF8E233F35d5',

    whitelist: '0x37E8386602d9EBEa2c56dd11d8E142290595f1b5',
};

interface ContractInstances {
    timelock: TimelockController,
    veSdtProxy: OrigamiVeSDTProxy,
    veSdt: IStakeDao_VeSDT,
    sdt: IERC20,
    controller: IStakeDao_GaugeController,
    whitelist: IStakeDao_WalletWhitelist,
}

function connectToContracts(STAKEDAO_DEPLOYED: StakeDaoDeployedContracts, GOV_DEPLOYED: GovernanceDeployedContracts, owner: Signer): ContractInstances {
    return {
        timelock: TimelockController__factory.connect(GOV_DEPLOYED.ORIGAMI.GOV_TIMELOCK, owner),
        veSdtProxy: OrigamiVeSDTProxy__factory.connect(STAKEDAO_DEPLOYED.ORIGAMI.STAKEDAO.VE_SDT_PROXY, owner),
        veSdt: IStakeDao_VeSDT__factory.connect(STAKEDAO_DEPLOYED.STAKEDAO.VE_SDT, owner),
        sdt: IERC20__factory.connect(STAKEDAO_DEPLOYED.STAKEDAO.SDT, owner),
        controller: IStakeDao_GaugeController__factory.connect(STAKEDAO_DEPLOYED.STAKEDAO.SDT_LOCKER_GAUGE_CONTROLLER, owner),
        whitelist: IStakeDao_WalletWhitelist__factory.connect(mainnetAddresses.whitelist, owner),
    }
}

async function impersonateAndFund(owner: Signer, address: string, amount: number): Promise<Signer> {
  const signer = await impersonateSigner(address);
  console.log("impersonateAndFund:", address, amount);
  if (amount > 0) {
    await mine(owner.sendTransaction({
        to: await signer.getAddress(),
        value: ethers.utils.parseEther(amount.toString()),
    }));
  }
  return signer;
}

async function acceptGov(contracts: ContractInstances, owner: Signer, contractToSet: Contract) {
    const now = Math.floor(Date.now() / 1000).toString();
    const eighteen_hours = 18*60*60;
    const encoded = contractToSet.interface.encodeFunctionData("acceptGov");
    await mine(contracts.timelock.connect(owner).schedule(
        contractToSet.address,
        0,
        encoded,
        ethers.utils.formatBytes32String(""),
        ethers.utils.formatBytes32String(now),
        eighteen_hours,
    ));
    await mineForwardSeconds(eighteen_hours);
    await mine(contracts.timelock.connect(owner).execute(
        contractToSet.address,
        0,
        encoded,
        ethers.utils.formatBytes32String(""),
        ethers.utils.formatBytes32String(now)
    ));

    console.log("Gov for:", contractToSet.address, "=", await contractToSet.gov());
}

// Have the timelock accept governance, and then give it back to owner
// as a test that the process works.
async function claimGov(contracts: ContractInstances, owner: Signer, contractToSet: Contract) {
    await acceptGov(contracts, owner, contractToSet);

    const now = Math.floor(Date.now() / 1000).toString();
    const eighteen_hours = 18*60*60;
    const encoded = contractToSet.interface.encodeFunctionData("proposeNewGov", [await owner.getAddress()]);
    await mine(contracts.timelock.connect(owner).schedule(
        contractToSet.address,
        0,
        encoded,
        ethers.utils.formatBytes32String(""),
        ethers.utils.formatBytes32String(now),
        eighteen_hours,
    ));
    await mineForwardSeconds(eighteen_hours);
    await mine(contracts.timelock.connect(owner).execute(
        contractToSet.address,
        0,
        encoded,
        ethers.utils.formatBytes32String(""),
        ethers.utils.formatBytes32String(now)
    ));

    await mine(contractToSet.connect(owner).acceptGov());
    console.log("Gov for:", contractToSet.address, "=", await contractToSet.gov());
}

async function main() {
    ensureExpectedEnvvars();
    const [owner, operator] = await ethers.getSigners();

    const STAKEDAO_DEPLOYED = stakeDaoDeployedContracts();
    const GOV_DEPLOYED = govDeployedContracts();
    console.log("owner addr:", await owner.getAddress());
    console.log("origami msig:", GOV_DEPLOYED.ORIGAMI.MULTISIG);
    console.log("origami timelock gov:", GOV_DEPLOYED.ORIGAMI.GOV_TIMELOCK);
    
    const origamiMultisig = await impersonateAndFund(owner, GOV_DEPLOYED.ORIGAMI.MULTISIG, 5);
    const contracts = connectToContracts(STAKEDAO_DEPLOYED, GOV_DEPLOYED, origamiMultisig);

    // Transfer some tetu/usdc LP to the proxy
    {
        const whale = await impersonateAndFund(owner, mainnetAddresses.sdtWhaleAddr, 2);
        await mine(contracts.sdt.connect(whale).transfer(contracts.veSdtProxy.address, ethers.utils.parseEther("10000")));
    }
    
    // Owner claim gov of the proxy and adds the operator
    {
        await claimGov(contracts, origamiMultisig, contracts.veSdtProxy);
        await mine(contracts.veSdtProxy.addOperator(operator.getAddress()));
    }

    // Add ourselves to the whitelist
    {
        const whitelistAdmin = await impersonateSigner(await contracts.whitelist.admin());
        await mine(contracts.whitelist.connect(whitelistAdmin).approveWallet(contracts.veSdtProxy.address));
    }

    console.log("** Create Lock **");
    {
        const lockDuration = 2 * 365 * 24 * 60 * 60;
        const lockEnd = await blockTimestamp() + lockDuration;
        const amount = ethers.utils.parseEther("100");
        await mine(contracts.veSdtProxy.connect(operator).veSDTCreateLock(amount, lockEnd));

        const locked = await contracts.veSdtProxy.veSDTLocked();
        console.log("veSdt locked amount:", locked.amount);
        console.log("veSdt locked end:", locked.end);
    }

    console.log("** Vote **");
    {
        const gauges = [mainnetAddresses.sdCRV_gauge, mainnetAddresses.sdANGLE_gauge];
        const weights = [5000, 2500];
        await mine(contracts.veSdtProxy.connect(operator).voteForSDTLockers(gauges, weights));
        console.log("Vote User Power:", await contracts.controller.vote_user_power(contracts.veSdtProxy.address));
    }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
