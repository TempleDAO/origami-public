import { ethers } from "ethers";

export const DEFAULT_SETTINGS = {
    /**
     * lovStEth dependencies and constants
     */
    LOV_STETH: {
      MIN_DEPOSIT_FEE_BPS: 0, // 0%
      MIN_EXIT_FEE_BPS: 50, // 0.5%
      FEE_LEVERAGE_FACTOR: 10e4, // targetting ~EE of the REBALANCE_AL_FLOOR
      REDEEMABLE_RESERVES_BUFFER: 0,
      PERFORMANCE_FEE_BPS: 500, // 5%

      USER_AL_FLOOR: ethers.utils.parseEther("1.112"),           // 89.92% LTV == 9.93x EE
      USER_AL_CEILING: ethers.utils.parseEther("1.162790"),      // 86% LTV == 7.14x EE
      REBALANCE_AL_FLOOR: ethers.utils.parseEther("1.112"),      // 89.92% LTV == 9.93x EE
      REBALANCE_AL_CEILING: ethers.utils.parseEther("1.149425"), // 87% LTV == 7.69x EE

      SPARK_EMODE: 1, // ETH e-mode

      MOCK_BORROW_LEND: {
        EMODE_MAX_LTV: 9000, // 90% LTV
        WSTETH_SUPPLY_CAP: ethers.utils.parseEther("1200000"), // 1.2mm wstETH supply cap
        WSTETH_SUPPLY_IR: ethers.utils.parseEther("0.0001"), // 0.01% supply APR for wstETH
        WETH_BORROW_IR: ethers.utils.parseEther("0.0203"), // 2.03% borrow APR for wETH
      },

      INITIAL_MAX_TOTAL_SUPPLY: ethers.utils.parseEther("10000000"),
    },

    ORACLES: {
      STETH_ETH: {
        STALENESS_THRESHOLD: 87300, // 1 days + 15 minutes
        MIN_THRESHOLD: ethers.utils.parseEther("0.99"), 
        MAX_THRESHOLD: ethers.utils.parseEther("1.01"), 
        HISTORIC_PRICE: ethers.utils.parseEther("1.0"), // Expect to be at 1:1 peg
        BASE_DECIMALS: 18,
        QUOTE_DECIMALS: 18,
      },
      WSTETH_ETH: {
        BASE_DECIMALS: 18,
        QUOTE_DECIMALS: 18,
      },
      // Doesn't matter what this is as long as it's consistent - only used internally
      // 115d ==> USD
      INTERNAL_USD_ADDRESS: "0x000000000000000000000000000000000000115d",
    },
    EXTERNAL: {
      STETH_INTEREST_RATE: ethers.utils.parseEther("0.04"),  // 4% APR, testnet only
    },
}