import { ethers } from "ethers";

const SEED_DEPOSIT_SIZE = ethers.utils.parseUnits("10", 6); // USDC
const BOYCO_MAX_TOTAL_SUPPLY = ethers.utils.parseEther("69000000"); // vault tokens

export const DEFAULT_SETTINGS = {
  VAULTS: {
    BOYCO_USDC_A: {
      TOKEN_SYMBOL: "oboy-USDC-a",
      TOKEN_NAME: "Origami Boyco USDC",
      SEED_DEPOSIT_SIZE: SEED_DEPOSIT_SIZE, 
      // Max of the seed deposit size plus the intended boyco max total supply
      MAX_TOTAL_SUPPLY: BOYCO_MAX_TOTAL_SUPPLY.add(
        SEED_DEPOSIT_SIZE.mul(ethers.utils.parseUnits("1", 12)) // scale up seed deposit to 18dp
      )
    }
  },

}