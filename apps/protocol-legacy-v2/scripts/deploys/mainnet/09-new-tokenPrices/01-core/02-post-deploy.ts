import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import {
  encodedErc4626TokenPrice,
  encodedMulPrice,
  encodedOraclePrice,
  encodedRepricingTokenPrice,
  encodedWstEthRatio,
  ensureExpectedEnvvars,
  mine,
  ZERO_ADDRESS,
} from '../../../helpers';
import { ContractInstances, connectToContracts, getDeployedContracts } from '../../contract-addresses';
import { ContractAddresses } from '../../contract-addresses/types';
import { DEFAULT_SETTINGS } from '../../default-settings';

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

async function setupPrices() {
  // 01-lov-sUSDe-a
  {
    // USDe/USD
    const encodedUsdeToUsd = encodedOraclePrice(
      ADDRS.EXTERNAL.REDSTONE.USDE_USD_ORACLE, 
      DEFAULT_SETTINGS.EXTERNAL.REDSTONE.USDE_USD_ORACLE.STALENESS_THRESHOLD
    );
    await mine(INSTANCES.CORE.TOKEN_PRICES.V2.setTokenPriceFunction(
      ADDRS.EXTERNAL.ETHENA.USDE_TOKEN, 
      encodedUsdeToUsd
    ));
  
    // sUSDe/USD
    const encodedSusdeToUsd = encodedOraclePrice(
      ADDRS.EXTERNAL.REDSTONE.SUSDE_USD_ORACLE, 
      DEFAULT_SETTINGS.EXTERNAL.REDSTONE.SUSDE_USD_ORACLE.STALENESS_THRESHOLD
    );
    await mine(INSTANCES.CORE.TOKEN_PRICES.V2.setTokenPriceFunction(
      ADDRS.EXTERNAL.ETHENA.SUSDE_TOKEN, 
      encodedSusdeToUsd
    ));

    // $lov-sUSDe
    await mine(INSTANCES.CORE.TOKEN_PRICES.V2.setTokenPriceFunction(
      ADDRS.LOV_SUSDE_A.TOKEN,
      encodedRepricingTokenPrice(ADDRS.LOV_SUSDE_A.TOKEN)
    ));
  }

  // 02-lov-USDe-a
  {
    // $lov-sUSDe
    await mine(INSTANCES.CORE.TOKEN_PRICES.V2.setTokenPriceFunction(
      ADDRS.LOV_USDE_A.TOKEN,
      encodedRepricingTokenPrice(ADDRS.LOV_USDE_A.TOKEN)
    ));
  }

  // 03-lov-weETH-a
  {
    // lov-weETH-a/USD
    await mine(INSTANCES.CORE.TOKEN_PRICES.V2.setTokenPriceFunction(
      ADDRS.LOV_WEETH_A.TOKEN,
      encodedRepricingTokenPrice(ADDRS.LOV_WEETH_A.TOKEN)
    ));
    
    // weETH/USD using the Redstone oracle
    const encodedWeEthToUsd = encodedOraclePrice(
      ADDRS.EXTERNAL.REDSTONE.WEETH_USD_ORACLE, 
      DEFAULT_SETTINGS.EXTERNAL.REDSTONE.WEETH_USD_ORACLE.STALENESS_THRESHOLD
    );
    await mine(INSTANCES.CORE.TOKEN_PRICES.V2.setTokenPriceFunction(
      ADDRS.EXTERNAL.ETHERFI.WEETH_TOKEN, 
      encodedWeEthToUsd
    ));
  }

  // 04-lov-ezETH-a
  {
    // lov-ezETH-a/USD
    await mine(INSTANCES.CORE.TOKEN_PRICES.V2.setTokenPriceFunction(
      ADDRS.LOV_EZETH_A.TOKEN,
      encodedRepricingTokenPrice(ADDRS.LOV_EZETH_A.TOKEN)
    ));

    // ETH/USD and wETH/USD
    const encodedEthToUsd = encodedOraclePrice(
      ADDRS.EXTERNAL.CHAINLINK.ETH_USD_ORACLE, 
      DEFAULT_SETTINGS.EXTERNAL.CHAINLINK.ETH_USD_ORACLE.STALENESS_THRESHOLD
    );
    await mine(INSTANCES.CORE.TOKEN_PRICES.V2.setTokenPriceFunction(
      ZERO_ADDRESS, 
      encodedEthToUsd,
    ));
    await mine(INSTANCES.CORE.TOKEN_PRICES.V2.setTokenPriceFunction(
      ADDRS.EXTERNAL.WETH_TOKEN, 
      encodedEthToUsd,
    ));

    // ezETH/USD = ezETH/ETH (Redstone oracle) * ETH/USD (Chainlink oracle)
    const encodedEzEthToEth = encodedOraclePrice(
      ADDRS.EXTERNAL.REDSTONE.EZETH_WETH_ORACLE, 
      DEFAULT_SETTINGS.EXTERNAL.REDSTONE.EZETH_WETH_ORACLE.STALENESS_THRESHOLD
    );
    const encodedEzEthToUsd = encodedMulPrice(
      encodedEzEthToEth,
      encodedEthToUsd
    );
    await mine(INSTANCES.CORE.TOKEN_PRICES.V2.setTokenPriceFunction(
      ADDRS.EXTERNAL.RENZO.EZETH_TOKEN, 
      encodedEzEthToUsd
    ));
  }

  // 05-lov-wstETH-a
  {
    // lov-wstETH-a/USD
    await mine(INSTANCES.CORE.TOKEN_PRICES.V2.setTokenPriceFunction(
      ADDRS.LOV_WSTETH_A.TOKEN,
      encodedRepricingTokenPrice(ADDRS.LOV_WSTETH_A.TOKEN)
    ));

    // stETH/USD = stETH/ETH * ETH/USD
    const encodedEthToUsd = encodedOraclePrice(
      ADDRS.EXTERNAL.CHAINLINK.ETH_USD_ORACLE, 
      DEFAULT_SETTINGS.EXTERNAL.CHAINLINK.ETH_USD_ORACLE.STALENESS_THRESHOLD
    );
    const encodedStEthToEth = encodedOraclePrice(
      ADDRS.EXTERNAL.CHAINLINK.STETH_ETH_ORACLE, 
      DEFAULT_SETTINGS.EXTERNAL.CHAINLINK.STETH_ETH_ORACLE.STALENESS_THRESHOLD
    );
    const encodedStEthToUsd = encodedMulPrice(encodedStEthToEth, encodedEthToUsd);
    await mine(INSTANCES.CORE.TOKEN_PRICES.V2.setTokenPriceFunction(
      ADDRS.EXTERNAL.LIDO.STETH_TOKEN, 
      encodedStEthToUsd
    ));

    // wstETH/USD = wstETH/stETH * stETH/USD
    await mine(INSTANCES.CORE.TOKEN_PRICES.V2.setTokenPriceFunction(
      ADDRS.EXTERNAL.LIDO.WSTETH_TOKEN,
      encodedMulPrice(
        encodedWstEthRatio(ADDRS.EXTERNAL.LIDO.STETH_TOKEN),
        encodedStEthToUsd
      )
    ));
  }

  // 06-lov-sUSDe-b
  {
    // $lov-sUSDe
    await mine(INSTANCES.CORE.TOKEN_PRICES.V2.setTokenPriceFunction(
      ADDRS.LOV_SUSDE_B.TOKEN,
      encodedRepricingTokenPrice(ADDRS.LOV_SUSDE_B.TOKEN)
    ));
  }

  // 07-lov-USDe-b
  {
    // $lov-USDE
    await mine(INSTANCES.CORE.TOKEN_PRICES.V2.setTokenPriceFunction(
      ADDRS.LOV_USDE_B.TOKEN,
      encodedRepricingTokenPrice(ADDRS.LOV_USDE_B.TOKEN)
    ));
  }

  // 08-lov-woETH-a
  {
    // $lov-woETH
    await mine(INSTANCES.CORE.TOKEN_PRICES.V2.setTokenPriceFunction(
      ADDRS.LOV_WOETH_A.TOKEN,
      encodedRepricingTokenPrice(ADDRS.LOV_WOETH_A.TOKEN)
    ));

    await mine(INSTANCES.CORE.TOKEN_PRICES.V2.setTokenPriceFunction(
      ADDRS.EXTERNAL.ORIGIN.OETH_TOKEN,
      encodedOraclePrice(
        ADDRS.EXTERNAL.CHAINLINK.ETH_USD_ORACLE, 
        DEFAULT_SETTINGS.EXTERNAL.CHAINLINK.ETH_USD_ORACLE.STALENESS_THRESHOLD
      )
    ));

    // woETH/USD = woETH/wETH (ERC-4626) * wETH/USD (Chainlink oracle)
    const encodedEzEthToUsd = encodedErc4626TokenPrice(
      ADDRS.EXTERNAL.ORIGIN.WOETH_TOKEN,
    );
    await mine(INSTANCES.CORE.TOKEN_PRICES.V2.setTokenPriceFunction(
      ADDRS.EXTERNAL.ORIGIN.WOETH_TOKEN, 
      encodedEzEthToUsd
    ));
  }

  // DAI and sDAI
  {
    await mine(INSTANCES.CORE.TOKEN_PRICES.V2.setTokenPriceFunction(
      ADDRS.EXTERNAL.MAKER_DAO.DAI_TOKEN,
      encodedOraclePrice(
        ADDRS.EXTERNAL.CHAINLINK.DAI_USD_ORACLE,
        DEFAULT_SETTINGS.EXTERNAL.CHAINLINK.DAI_USD_ORACLE.STALENESS_THRESHOLD
      )
    ));

    await mine(INSTANCES.CORE.TOKEN_PRICES.V2.setTokenPriceFunction(
      ADDRS.EXTERNAL.MAKER_DAO.SDAI_TOKEN,
      encodedMulPrice(
        encodedErc4626TokenPrice(ADDRS.EXTERNAL.MAKER_DAO.SDAI_TOKEN),
        encodedOraclePrice(
          ADDRS.EXTERNAL.CHAINLINK.DAI_USD_ORACLE, 
          DEFAULT_SETTINGS.EXTERNAL.CHAINLINK.DAI_USD_ORACLE.STALENESS_THRESHOLD
        ),
      ),
    ));
  }
}

async function main() {
  ensureExpectedEnvvars();
  
  const [owner] = await ethers.getSigners();
  ADDRS = getDeployedContracts();
  INSTANCES = connectToContracts(owner);

  await setupPrices();
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
