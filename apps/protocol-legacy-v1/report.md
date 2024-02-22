 Sūrya's Description Report

 Files Description Table


| File Name                                                                                           | SHA-1 Hash                               |
| --------------------------------------------------------------------------------------------------- | ---------------------------------------- |
| /Users/frontier/git/origami/apps/protocol/contracts/investments/OrigamiInvestmentVault.sol          | 9d50ad87f16fa78da0b4c2360b9a66a835bd0303 |
| /Users/frontier/git/origami/apps/protocol/contracts/investments/OrigamiInvestment.sol               | f5ca838121333fe1e9f0b0337b1cb4ac47a50a47 |
| /Users/frontier/git/origami/apps/protocol/contracts/investments/gmx/OrigamiGmxManager.sol           | 1e35665962f3f287d579a2469845774838396f57 |
| /Users/frontier/git/origami/apps/protocol/contracts/investments/gmx/OrigamiGmxInvestment.sol        | 3d0c53cc50f6ab52b6598673964eb23560a29d1d |
| /Users/frontier/git/origami/apps/protocol/contracts/investments/gmx/OrigamiGmxRewardsAggregator.sol | f83ec79fa46fd1312aa50987908603dc2b9f3dc6 |
| /Users/frontier/git/origami/apps/protocol/contracts/investments/gmx/OrigamiGlpInvestment.sol        | 44d2988b94b98722724fdedc7ead00284e71f825 |
| /Users/frontier/git/origami/apps/protocol/contracts/investments/gmx/OrigamiGmxEarnAccount.sol       | c0b696741031285d3e725957c466382c0b17aa13 |


 Contracts Description Table


|            Contract             |            Type             |     |                                         Bases                                         |                |                   |
| :-----------------------------: | :-------------------------: | --- | :-----------------------------------------------------------------------------------: | :------------: | :---------------: |
|                └                |      **Function Name**      |     |                                    **Visibility**                                     | **Mutability** |   **Modifiers**   |
|                                 |                             |     |                                                                                       |                |                   |
|   **OrigamiInvestmentVault**    |       Implementation        |     |               IOrigamiInvestmentVault, RepricingToken, ReentrancyGuard                |                |                   |
|                └                |        <Constructor>        |     |                                      Public ❗️                                      |      🛑       |  RepricingToken   |
|                └                |         apiVersion          |     |                                     External ❗️                                     |                |      NO❗️       |
|                └                |    areInvestmentsPaused     |     |                                     External ❗️                                     |                |      NO❗️       |
|                └                |       areExitsPaused        |     |                                     External ❗️                                     |                |      NO❗️       |
|                └                |    setInvestmentManager     |     |                                     External ❗️                                     |      🛑       |     onlyOwner     |
|                └                |       setTokenPrices        |     |                                     External ❗️                                     |      🛑       |     onlyOwner     |
|                └                |      setPerformanceFee      |     |                                     External ❗️                                     |      🛑       |     onlyOwner     |
|                └                |     appendReserveToken      |     |                                      Private 🔐                                      |                |                   |
|                └                |    acceptedInvestTokens     |     |                                     External ❗️                                     |                |      NO❗️       |
|                └                |     acceptedExitTokens      |     |                                     External ❗️                                     |                |      NO❗️       |
|                └                |        applySlippage        |     |                                     Internal 🔒                                      |                |                   |
|                └                |         investQuote         |     |                                     External ❗️                                     |                |      NO❗️       |
|                └                |       investWithToken       |     |                                     External ❗️                                     |      🛑       |   nonReentrant    |
|                └                |      investWithNative       |     |                                     External ❗️                                     |      💵       |   nonReentrant    |
|                └                |          exitQuote          |     |                                     External ❗️                                     |                |      NO❗️       |
|                └                |         exitToToken         |     |                                     External ❗️                                     |      🛑       |      NO❗️       |
|                └                |        exitToNative         |     |                                     External ❗️                                     |      🛑       |   nonReentrant    |
|                └                |             apr             |     |                                     External ❗️                                     |                |      NO❗️       |
|                                 |                             |     |                                                                                       |                |                   |
|      **OrigamiInvestment**      |       Implementation        |     |                  IOrigamiInvestment, MintableToken, ReentrancyGuard                   |                |                   |
|                └                |         apiVersion          |     |                                     External ❗️                                     |                |      NO❗️       |
|                └                |        <Constructor>        |     |                                      Public ❗️                                      |      🛑       |   MintableToken   |
|                                 |                             |     |                                                                                       |                |                   |
|      **OrigamiGmxManager**      |       Implementation        |     |                        IOrigamiGmxManager, Ownable, Operators                         |                |                   |
|                └                |        <Constructor>        |     |                                      Public ❗️                                      |      🛑       |      NO❗️       |
|                └                |      initGmxContracts       |     |                                      Public ❗️                                      |      🛑       |     onlyOwner     |
|                └                |           paused            |     |                                     External ❗️                                     |                |      NO❗️       |
|                └                |          setPaused          |     |                                     External ❗️                                     |      🛑       |     onlyOwner     |
|                └                |    setOGmxRewardsFeeRate    |     |                                     External ❗️                                     |      🛑       |     onlyOwner     |
|                └                |     setEsGmxVestingRate     |     |                                     External ❗️                                     |      🛑       |     onlyOwner     |
|                └                |       setSellFeeRate        |     |                                     External ❗️                                     |      🛑       |     onlyOwner     |
|                └                |       setFeeCollector       |     |                                     External ❗️                                     |      🛑       |     onlyOwner     |
|                └                |    setPrimaryEarnAccount    |     |                                     External ❗️                                     |      🛑       |     onlyOwner     |
|                └                |   setSecondaryEarnAccount   |     |                                     External ❗️                                     |      🛑       |     onlyOwner     |
|                └                |    setRewardsAggregators    |     |                                     External ❗️                                     |      🛑       |     onlyOwner     |
|                └                |         addOperator         |     |                                     External ❗️                                     |      🛑       |     onlyOwner     |
|                └                |       removeOperator        |     |                                     External ❗️                                     |      🛑       |     onlyOwner     |
|                └                |      rewardTokensList       |     |                                     External ❗️                                     |                |      NO❗️       |
|                └                |     harvestableRewards      |     |                                     External ❗️                                     |                |      NO❗️       |
|                └                |    projectedRewardRates     |     |                                     External ❗️                                     |                |      NO❗️       |
|                └                |       harvestRewards        |     |                                     External ❗️                                     |      🛑       |   onlyOperators   |
|                └                |    _processNativeRewards    |     |                                     Internal 🔒                                      |      🛑       |                   |
|                └                |   harvestSecondaryRewards   |     |                                     External ❗️                                     |      🛑       |   onlyOperators   |
|                └                | harvestableSecondaryRewards |     |                                     External ❗️                                     |                |      NO❗️       |
|                └                |          applyGmx           |     |                                     External ❗️                                     |      🛑       |   onlyOperators   |
|                └                |          _applyGmx          |     |                                     Internal 🔒                                      |      🛑       |                   |
|                └                |     acceptedOGmxTokens      |     |                                     External ❗️                                     |                |      NO❗️       |
|                └                |       investOGmxQuote       |     |                                     External ❗️                                     |                |      NO❗️       |
|                └                |         investOGmx          |     |                                     External ❗️                                     |      🛑       |   onlyOperators   |
|                └                |        exitOGmxQuote        |     |                                     External ❗️                                     |                |      NO❗️       |
|                └                |          exitOGmx           |     |                                     External ❗️                                     |      🛑       |   onlyOperators   |
|                └                |      acceptedGlpTokens      |     |                                     External ❗️                                     |                |      NO❗️       |
|                └                |        applySlippage        |     |                                     Internal 🔒                                      |                |                   |
|                └                |       investOGlpQuote       |     |                                     External ❗️                                     |                |      NO❗️       |
|                └                |         investOGlp          |     |                                     External ❗️                                     |      🛑       |   onlyOperators   |
|                └                |        exitOGlpQuote        |     |                                     External ❗️                                     |                |      NO❗️       |
|                └                |          exitOGlp           |     |                                     External ❗️                                     |      🛑       |   onlyOperators   |
|                └                |        buyUsdgQuote         |     |                                     Internal 🔒                                      |                |                   |
|                └                |        sellUsdgQuote        |     |                                     Internal 🔒                                      |                |                   |
|                └                |      getFeeBasisPoints      |     |                                     Internal 🔒                                      |                |                   |
|                └                |        recoverToken         |     |                                     External ❗️                                     |      🛑       |     onlyOwner     |
|                                 |                             |     |                                                                                       |                |                   |
|    **OrigamiGmxInvestment**     |       Implementation        |     |                                   OrigamiInvestment                                   |                |                   |
|                └                |        <Constructor>        |     |                                      Public ❗️                                      |      🛑       | OrigamiInvestment |
|                └                |    setOrigamiGmxManager     |     |                                     External ❗️                                     |      🛑       |     onlyOwner     |
|                └                |    acceptedInvestTokens     |     |                                     External ❗️                                     |                |      NO❗️       |
|                └                |     acceptedExitTokens      |     |                                     External ❗️                                     |                |      NO❗️       |
|                └                |    areInvestmentsPaused     |     |                                     External ❗️                                     |                |      NO❗️       |
|                └                |       areExitsPaused        |     |                                     External ❗️                                     |                |      NO❗️       |
|                └                |         investQuote         |     |                                     External ❗️                                     |                |      NO❗️       |
|                └                |       investWithToken       |     |                                     External ❗️                                     |      🛑       |   nonReentrant    |
|                └                |      investWithNative       |     |                                     External ❗️                                     |      💵       |      NO❗️       |
|                └                |          exitQuote          |     |                                     External ❗️                                     |                |      NO❗️       |
|                └                |         exitToToken         |     |                                     External ❗️                                     |      🛑       |   nonReentrant    |
|                └                |        exitToNative         |     |                                     External ❗️                                     |                |      NO❗️       |
|                                 |                             |     |                                                                                       |                |                   |
| **OrigamiGmxRewardsAggregator** |       Implementation        |     |                     IOrigamiInvestmentManager, Ownable, Operators                     |                |                   |
|                └                |        <Constructor>        |     |                                      Public ❗️                                      |      🛑       |      NO❗️       |
|                └                |         addOperator         |     |                                     External ❗️                                     |      🛑       |     onlyOwner     |
|                └                |       removeOperator        |     |                                     External ❗️                                     |      🛑       |     onlyOwner     |
|                └                |    setOrigamiGmxManagers    |     |                                     External ❗️                                     |      🛑       |     onlyOwner     |
|                └                | setPerformanceFeeCollector  |     |                                     External ❗️                                     |      🛑       |     onlyOwner     |
|                └                |      rewardTokensList       |     |                                     External ❗️                                     |                |      NO❗️       |
|                └                |     harvestableRewards      |     |                                     External ❗️                                     |                |      NO❗️       |
|                └                |    projectedRewardRates     |     |                                     External ❗️                                     |                |      NO❗️       |
|                └                |       harvestRewards        |     |                                     External ❗️                                     |      🛑       |   onlyOperators   |
|                └                |    _compoundOvGmxRewards    |     |                                     Internal 🔒                                      |      🛑       |                   |
|                └                |    _compoundOvGlpRewards    |     |                                     Internal 🔒                                      |      🛑       |                   |
|                └                |        _addReserves         |     |                                     Internal 🔒                                      |      🛑       |                   |
|                └                |     _swapAssetToAsset0x     |     |                                     Internal 🔒                                      |      🛑       |                   |
|                └                |        recoverToken         |     |                                     External ❗️                                     |      🛑       |     onlyOwner     |
|                                 |                             |     |                                                                                       |                |                   |
|    **OrigamiGlpInvestment**     |       Implementation        |     |                                   OrigamiInvestment                                   |                |                   |
|                └                |        <Constructor>        |     |                                      Public ❗️                                      |      🛑       | OrigamiInvestment |
|                └                |       <Receive Ether>       |     |                                     External ❗️                                     |      💵       |      NO❗️       |
|                └                |    setOrigamiGlpManager     |     |                                     External ❗️                                     |      🛑       |     onlyOwner     |
|                └                |    acceptedInvestTokens     |     |                                     External ❗️                                     |                |      NO❗️       |
|                └                |     acceptedExitTokens      |     |                                     External ❗️                                     |                |      NO❗️       |
|                └                |    areInvestmentsPaused     |     |                                     External ❗️                                     |                |      NO❗️       |
|                └                |       areExitsPaused        |     |                                     External ❗️                                     |                |      NO❗️       |
|                └                |         investQuote         |     |                                     External ❗️                                     |                |      NO❗️       |
|                └                |       investWithToken       |     |                                     External ❗️                                     |      🛑       |   nonReentrant    |
|                └                |      investWithNative       |     |                                     External ❗️                                     |      💵       |   nonReentrant    |
|                └                |          exitQuote          |     |                                     External ❗️                                     |                |      NO❗️       |
|                └                |         exitToToken         |     |                                     External ❗️                                     |      🛑       |   nonReentrant    |
|                └                |        exitToNative         |     |                                     External ❗️                                     |      🛑       |   nonReentrant    |
|                                 |                             |     |                                                                                       |                |                   |
|    **OrigamiGmxEarnAccount**    |       Implementation        |     | IOrigamiGmxEarnAccount, Initializable, OwnableUpgradeable, Operators, UUPSUpgradeable |                |                   |
|                └                |        <Constructor>        |     |                                      Public ❗️                                      |      🛑       |      NO❗️       |
|                └                |         initialize          |     |                                     External ❗️                                     |      🛑       |    initializer    |
|                └                |      _authorizeUpgrade      |     |                                     Internal 🔒                                      |      🛑       |     onlyOwner     |
|                └                |      initGmxContracts       |     |                                      Public ❗️                                      |      🛑       |     onlyOwner     |
|                └                |         addOperator         |     |                                     External ❗️                                     |      🛑       |     onlyOwner     |
|                └                |       removeOperator        |     |                                     External ❗️                                     |      🛑       |     onlyOwner     |
|                └                |          stakeGmx           |     |                                     External ❗️                                     |      🛑       |   onlyOperators   |
|                └                |         unstakeGmx          |     |                                     External ❗️                                     |      🛑       |   onlyOperators   |
|                └                |         stakeEsGmx          |     |                                     External ❗️                                     |      🛑       |   onlyOperators   |
|                └                |        unstakeEsGmx         |     |                                     External ❗️                                     |      🛑       |   onlyOperators   |
|                └                |       mintAndStakeGlp       |     |                                     External ❗️                                     |      🛑       |   onlyOperators   |
|                └                |     unstakeAndRedeemGlp     |     |                                     External ❗️                                     |      🛑       |   onlyOperators   |
|                └                |      transferStakedGlp      |     |                                     External ❗️                                     |      🛑       |   onlyOperators   |
|                └                | glpInvestmentCooldownExpiry |     |                                      Public ❗️                                      |                |      NO❗️       |
|                └                |  _setGlpInvestmentsPaused   |     |                                     Internal 🔒                                      |      🛑       |                   |
|                └                |  transferStakedGlpOrPause   |     |                                     External ❗️                                     |      🛑       |   onlyOperators   |
|                └                |         rewardRates         |     |                                     External ❗️                                     |                |      NO❗️       |
|                └                |     harvestableRewards      |     |                                     External ❗️                                     |                |      NO❗️       |
|                └                |          positions          |     |                                     External ❗️                                     |                |      NO❗️       |
|                └                |       harvestRewards        |     |                                     External ❗️                                     |      🛑       |   onlyOperators   |
|                └                |        handleRewards        |     |                                     External ❗️                                     |      🛑       |   onlyOperators   |
|                └                |      _handleGmxRewards      |     |                                     Internal 🔒                                      |      🛑       |                   |
|                └                |   subtractWithFloorAtZero   |     |                                     Internal 🔒                                      |                |                   |
|                └                |   depositIntoEsGmxVesting   |     |                                     External ❗️                                     |      🛑       |   onlyOperators   |
|                └                |  withdrawFromEsGmxVesting   |     |                                     External ❗️                                     |      🛑       |   onlyOperators   |
|                └                |       _rewardsPerSec        |     |                                     Internal 🔒                                      |                |                   |


 Legend

| Symbol | Meaning                   |
| :----: | ------------------------- |
|  🛑   | Function can modify state |
|  💵   | Function is payable       |
