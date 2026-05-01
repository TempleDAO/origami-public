import { ethers } from "hardhat";
import { ensureExpectedEnvvars } from "../helpers";
import { ContractInstances, connectToContracts1, getDeployedContracts1 } from "./contract-addresses";
import { ContractAddresses } from "./contract-addresses/types";

export interface DeployContext {
  owner: string;
  ADDRS: ContractAddresses,
  INSTANCES: ContractInstances,
}

export async function getDeployContext(dirname: string) {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = await getDeployedContracts1(dirname);
  const INSTANCES = connectToContracts1(owner, ADDRS);
  return {
    owner,
    ADDRS,
    INSTANCES,
  }
}
