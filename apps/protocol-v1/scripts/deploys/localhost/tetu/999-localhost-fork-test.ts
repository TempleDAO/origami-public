import { BigNumber, Contract, Signer } from 'ethers';
import { ethers } from 'hardhat';
import { impersonateSigner, mineForwardSeconds } from '../../../../test/helpers';
import { 
    OrigamiVeTetuProxy, OrigamiVeTetuProxy__factory,
    TimelockController, TimelockController__factory,
    IERC20, IERC20__factory,
    IVeTetu, IVeTetu__factory,
    ITetuVoter, ITetuVoter__factory,
} from '../../../../typechain';
import {
    ensureExpectedEnvvars,
    mine,
} from '../../helpers';
import { TetuDeployedContracts, getDeployedContracts as tetuDeployedContracts } from '../../polygon/tetu/contract-addresses';
import { GovernanceDeployedContracts, getDeployedContracts as govDeployedContracts } from '../../polygon/governance/contract-addresses';

const tetuUsdc8020Addr = '0xE2f706EF1f7240b803AAe877C9C762644bb808d8';
const tetuUsdc8020WhaleAddr = '0x7d3e18a41d4a822dab621db1d6132d701da9e90d';

interface ContractInstances {
    timelock: TimelockController,
    veTetuProxy: OrigamiVeTetuProxy,
    tetuUsdc8020: IERC20,
    veTetu: IVeTetu,
    tetuVoter: ITetuVoter,
}

function connectToContracts(TETU_DEPLOYED: TetuDeployedContracts, GOV_DEPLOYED: GovernanceDeployedContracts, owner: Signer): ContractInstances {
    return {
        timelock: TimelockController__factory.connect(GOV_DEPLOYED.ORIGAMI.GOV_TIMELOCK, owner),
        veTetuProxy: OrigamiVeTetuProxy__factory.connect(TETU_DEPLOYED.ORIGAMI.TETU.VE_TETU_PROXY, owner),
        tetuUsdc8020: IERC20__factory.connect(tetuUsdc8020Addr, owner),
        veTetu: IVeTetu__factory.connect(TETU_DEPLOYED.TETU.VE_TETU, owner),
        tetuVoter: ITetuVoter__factory.connect(TETU_DEPLOYED.TETU.TETU_VOTER, owner),
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

    const TETU_DEPLOYED = tetuDeployedContracts();
    const GOV_DEPLOYED = govDeployedContracts();
    console.log("owner addr:", await owner.getAddress());
    console.log("origami msig:", GOV_DEPLOYED.ORIGAMI.MULTISIG);
    console.log("origami timelock gov:", GOV_DEPLOYED.ORIGAMI.GOV_TIMELOCK);
    
    const origamiMultisig = await impersonateAndFund(owner, GOV_DEPLOYED.ORIGAMI.MULTISIG, 5);
    const contracts = connectToContracts(TETU_DEPLOYED, GOV_DEPLOYED, origamiMultisig);

    // Transfer some tetu/usdc LP to the proxy
    {
        const tetuUsdc8020Whale = await impersonateAndFund(owner, tetuUsdc8020WhaleAddr, 2);
        await mine(contracts.tetuUsdc8020.connect(tetuUsdc8020Whale).transfer(contracts.veTetuProxy.address, ethers.utils.parseEther("1000")));
    }
    
    // Owner claim gov of the proxy and adds the operator
    {
        await claimGov(contracts, origamiMultisig, contracts.veTetuProxy);
        await mine(contracts.veTetuProxy.addOperator(operator.getAddress()));
    }

    let tokenId: BigNumber;
    console.log("** Create Lock **");
    {
        const lockDuration = 10 * 7 * 24 * 60 * 60;
        const amount = ethers.utils.parseEther("100");
        await mine(contracts.veTetuProxy.connect(operator).createLock(tetuUsdc8020Addr, amount, lockDuration));

        console.log("veTetu locked amount:", await contracts.veTetuProxy.veTetuLockedAmount(tetuUsdc8020Addr));
        console.log("veTetu locked end:", await contracts.veTetuProxy.veTetuLockedAmount(tetuUsdc8020Addr));
        console.log("veTetu total voting balance:", await contracts.veTetuProxy.veTetuVotingBalance());
        tokenId = await contracts.veTetu.tokenOfOwnerByIndex(contracts.veTetuProxy.address, 0);
        console.log("veTetu token id:", tokenId);
        console.log("veTetu locked end:", await contracts.veTetuProxy.veTetuLockedEnd(tokenId));
    }

    console.log("** Vote **");
    {
        const vaults = [contracts.tetuVoter.validVaults(0),contracts.tetuVoter.validVaults(1)];
        const weights = [25, 75];
        await mine(contracts.veTetuProxy.connect(operator).vote(tokenId, vaults, weights));

        console.log("veTetu votes vault 0:", await contracts.tetuVoter.votes(tokenId, vaults[0]));
        console.log("veTetu votes vault 1:", await contracts.tetuVoter.votes(tokenId, vaults[1]));
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
