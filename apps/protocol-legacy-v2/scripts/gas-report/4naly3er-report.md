# Report


## Gas Optimizations


| |Issue|Instances|
|-|:-|:-:|
| [GAS-1](#GAS-1) | Using bools for storage incurs overhead | 10 |
| [GAS-2](#GAS-2) | For Operations that will not overflow, you could use unchecked | 1082 |
| [GAS-3](#GAS-3) | Don't initialize variables with default value | 3 |
| [GAS-4](#GAS-4) | Functions guaranteed to revert when called by normal users can be marked `payable` | 81 |
| [GAS-5](#GAS-5) | Using `private` rather than `public` for constants, saves gas | 13 |
### <a name="GAS-1"></a>[GAS-1] Using bools for storage incurs overhead
Use uint256(1) and uint256(2) for true/false to avoid a Gwarmaccess (100 gas), and to avoid Gsset (20000 gas) when changing from ‘false’ to ‘true’, after having been ‘true’ in the past. See [source](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/58f635312aa21f947cae5f8578638a85aa2519f5/contracts/security/ReentrancyGuard.sol#L23-L27).

*Instances (10)*:
```solidity
File: contracts/common/MintableToken.sol

20:     mapping(address account => bool canMint) internal _minters;

```

```solidity
File: contracts/common/access/OrigamiElevatedAccessBase.sol

21:     mapping(address => mapping(bytes4 => bool)) public override explicitFunctionAccess;

```

```solidity
File: contracts/common/access/Whitelisted.sol

17:     bool public override allowAll;

22:     mapping(address account => bool allowed) public override allowedAccounts;

```

```solidity
File: contracts/common/oracle/OrigamiStableChainlinkOracle.sol

35:     bool public immutable spotPricePrecisionScaleDown;

```

```solidity
File: contracts/investments/lending/OrigamiDebtToken.sol

38:     mapping(address account => bool canMint) public override minters;

```

```solidity
File: contracts/investments/lending/OrigamiLendingClerk.sol

74:     bool public override globalBorrowPaused;

79:     bool public override globalRepayPaused;

```

```solidity
File: contracts/investments/lending/idleStrategy/OrigamiIdleStrategyManager.sol

39:     bool public override depositsEnabled;

```

```solidity
File: contracts/investments/util/OrigamiManagerPausable.sol

17:     mapping(address account => bool canPause) public pausers;

```

### <a name="GAS-2"></a>[GAS-2] For Operations that will not overflow, you could use unchecked

*Instances (1082)*:
```solidity
File: contracts/common/MintableToken.sol

5: import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

5: import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

5: import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

5: import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

6: import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

6: import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

6: import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

6: import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

6: import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

7: import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

7: import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

7: import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

7: import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

7: import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

8: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

8: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

8: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

8: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

9: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

9: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

9: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

9: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

9: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

11: import { IMintableToken } from "contracts/interfaces/common/IMintableToken.sol";

11: import { IMintableToken } from "contracts/interfaces/common/IMintableToken.sol";

11: import { IMintableToken } from "contracts/interfaces/common/IMintableToken.sol";

12: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

12: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

13: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

13: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

13: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

```

```solidity
File: contracts/common/RepricingToken.sol

5: import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

5: import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

5: import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

5: import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

6: import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

6: import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

6: import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

6: import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

6: import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

7: import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

7: import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

7: import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

7: import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

7: import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

8: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

8: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

8: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

8: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

9: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

9: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

9: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

9: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

9: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

11: import { IRepricingToken } from "contracts/interfaces/common/IRepricingToken.sol";

11: import { IRepricingToken } from "contracts/interfaces/common/IRepricingToken.sol";

11: import { IRepricingToken } from "contracts/interfaces/common/IRepricingToken.sol";

12: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

12: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

13: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

13: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

13: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

14: import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

14: import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

87:             if (_amount > (bal - (vestedReserves + pendingReserves))) revert CommonEventsAndErrors.InvalidAmount(_token, _amount);

87:             if (_amount > (bal - (vestedReserves + pendingReserves))) revert CommonEventsAndErrors.InvalidAmount(_token, _amount);

103:         return vestedReserves + accrued;

108:         return sharesToReserves(10 ** decimals());

108:         return sharesToReserves(10 ** decimals());

139:         uint256 secsSinceLastCheckpoint = block.timestamp - lastVestingCheckpoint;

145:             : _pendingReserves * secsSinceLastCheckpoint / _vestingDuration;

145:             : _pendingReserves * secsSinceLastCheckpoint / _vestingDuration;

148:         outstanding = _pendingReserves - accrued;

168:         if (block.timestamp - lastVestingCheckpoint < reservesVestingDuration) revert CannotCheckpointReserves(block.timestamp - lastVestingCheckpoint, reservesVestingDuration);

168:         if (block.timestamp - lastVestingCheckpoint < reservesVestingDuration) revert CannotCheckpointReserves(block.timestamp - lastVestingCheckpoint, reservesVestingDuration);

183:                 pendingReserves * 365 days,

184:                 reservesVestingDuration,  // reserve rewards per year

184:                 reservesVestingDuration,  // reserve rewards per year

186:             ) / _vestedReserves // the last snapshot of vested rewards

186:             ) / _vestedReserves // the last snapshot of vested rewards

186:             ) / _vestedReserves // the last snapshot of vested rewards

202:         vestedReserves += reserveTokenAmount;

211:         if (IERC20(reserveToken).balanceOf(address(this)) < (vestedReserves + pendingReserves)) {

212:             revert CommonEventsAndErrors.InsufficientBalance(reserveToken, vestedReserves + pendingReserves, IERC20(reserveToken).balanceOf(address(this)));

231:         vestedReserves -= reserveTokenAmount;

246:         uint256 _vestedReserves = vestedReserves + accrued;

249:         pendingReserves = outstanding + newReserves;

```

```solidity
File: contracts/common/access/OrigamiElevatedAccess.sol

5: import { OrigamiElevatedAccessBase } from "contracts/common/access/OrigamiElevatedAccessBase.sol";

5: import { OrigamiElevatedAccessBase } from "contracts/common/access/OrigamiElevatedAccessBase.sol";

5: import { OrigamiElevatedAccessBase } from "contracts/common/access/OrigamiElevatedAccessBase.sol";

```

```solidity
File: contracts/common/access/OrigamiElevatedAccessBase.sol

5: import { IOrigamiElevatedAccess } from "contracts/interfaces/common/access/IOrigamiElevatedAccess.sol";

5: import { IOrigamiElevatedAccess } from "contracts/interfaces/common/access/IOrigamiElevatedAccess.sol";

5: import { IOrigamiElevatedAccess } from "contracts/interfaces/common/access/IOrigamiElevatedAccess.sol";

5: import { IOrigamiElevatedAccess } from "contracts/interfaces/common/access/IOrigamiElevatedAccess.sol";

6: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

6: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

62:         for (uint256 i; i < _length; ++i) {

62:         for (uint256 i; i < _length; ++i) {

```

```solidity
File: contracts/common/access/Whitelisted.sol

5: import { IWhitelisted } from "contracts/interfaces/common/access/IWhitelisted.sol";

5: import { IWhitelisted } from "contracts/interfaces/common/access/IWhitelisted.sol";

5: import { IWhitelisted } from "contracts/interfaces/common/access/IWhitelisted.sol";

5: import { IWhitelisted } from "contracts/interfaces/common/access/IWhitelisted.sol";

6: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

6: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

6: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

7: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

7: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

```

```solidity
File: contracts/common/borrowAndLend/OrigamiAaveV3BorrowAndLend.sol

5: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

5: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

5: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

5: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

6: import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

6: import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

6: import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

6: import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

6: import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

7: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

7: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

7: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

7: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

7: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

9: import { WadRayMath as AaveWadRayMath} from "@aave/core-v3/contracts/protocol/libraries/math/WadRayMath.sol";

9: import { WadRayMath as AaveWadRayMath} from "@aave/core-v3/contracts/protocol/libraries/math/WadRayMath.sol";

9: import { WadRayMath as AaveWadRayMath} from "@aave/core-v3/contracts/protocol/libraries/math/WadRayMath.sol";

9: import { WadRayMath as AaveWadRayMath} from "@aave/core-v3/contracts/protocol/libraries/math/WadRayMath.sol";

9: import { WadRayMath as AaveWadRayMath} from "@aave/core-v3/contracts/protocol/libraries/math/WadRayMath.sol";

9: import { WadRayMath as AaveWadRayMath} from "@aave/core-v3/contracts/protocol/libraries/math/WadRayMath.sol";

9: import { WadRayMath as AaveWadRayMath} from "@aave/core-v3/contracts/protocol/libraries/math/WadRayMath.sol";

10: import { ReserveConfiguration as AaveReserveConfiguration } from "@aave/core-v3/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";

10: import { ReserveConfiguration as AaveReserveConfiguration } from "@aave/core-v3/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";

10: import { ReserveConfiguration as AaveReserveConfiguration } from "@aave/core-v3/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";

10: import { ReserveConfiguration as AaveReserveConfiguration } from "@aave/core-v3/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";

10: import { ReserveConfiguration as AaveReserveConfiguration } from "@aave/core-v3/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";

10: import { ReserveConfiguration as AaveReserveConfiguration } from "@aave/core-v3/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";

10: import { ReserveConfiguration as AaveReserveConfiguration } from "@aave/core-v3/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";

11: import { DataTypes as AaveDataTypes } from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";

11: import { DataTypes as AaveDataTypes } from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";

11: import { DataTypes as AaveDataTypes } from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";

11: import { DataTypes as AaveDataTypes } from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";

11: import { DataTypes as AaveDataTypes } from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";

11: import { DataTypes as AaveDataTypes } from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";

11: import { DataTypes as AaveDataTypes } from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";

12: import { IPool as IAavePool } from "@aave/core-v3/contracts/interfaces/IPool.sol";

12: import { IPool as IAavePool } from "@aave/core-v3/contracts/interfaces/IPool.sol";

12: import { IPool as IAavePool } from "@aave/core-v3/contracts/interfaces/IPool.sol";

12: import { IPool as IAavePool } from "@aave/core-v3/contracts/interfaces/IPool.sol";

12: import { IPool as IAavePool } from "@aave/core-v3/contracts/interfaces/IPool.sol";

13: import { IAToken as IAaveAToken } from "@aave/core-v3/contracts/interfaces/IAToken.sol";

13: import { IAToken as IAaveAToken } from "@aave/core-v3/contracts/interfaces/IAToken.sol";

13: import { IAToken as IAaveAToken } from "@aave/core-v3/contracts/interfaces/IAToken.sol";

13: import { IAToken as IAaveAToken } from "@aave/core-v3/contracts/interfaces/IAToken.sol";

13: import { IAToken as IAaveAToken } from "@aave/core-v3/contracts/interfaces/IAToken.sol";

15: import { IOrigamiAaveV3BorrowAndLend } from "contracts/interfaces/common/borrowAndLend/IOrigamiAaveV3BorrowAndLend.sol";

15: import { IOrigamiAaveV3BorrowAndLend } from "contracts/interfaces/common/borrowAndLend/IOrigamiAaveV3BorrowAndLend.sol";

15: import { IOrigamiAaveV3BorrowAndLend } from "contracts/interfaces/common/borrowAndLend/IOrigamiAaveV3BorrowAndLend.sol";

15: import { IOrigamiAaveV3BorrowAndLend } from "contracts/interfaces/common/borrowAndLend/IOrigamiAaveV3BorrowAndLend.sol";

16: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

16: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

17: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

17: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

17: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

226:             if (amount > (bal - suppliedBalance())) revert CommonEventsAndErrors.InvalidAmount(token, amount);

266:         return alRatio >= LTV_TO_AL_FACTOR / _aaveLtv;

288:         supplyCap = _reserveData.configuration.getSupplyCap() * (10 ** _reserveData.configuration.getDecimals());

288:         supplyCap = _reserveData.configuration.getSupplyCap() * (10 ** _reserveData.configuration.getDecimals());

288:         supplyCap = _reserveData.configuration.getSupplyCap() * (10 ** _reserveData.configuration.getDecimals());

295:                 aaveAToken.scaledTotalSupply() +

301:             available = supplyCap > utilised ? supplyCap - utilised : 0;

328:         _aTokenShares += aaveAToken.scaledBalanceOf(address(this)) - sharesBefore;

328:         _aTokenShares += aaveAToken.scaledBalanceOf(address(this)) - sharesBefore;

334:         _aTokenShares = _aTokenShares + aaveAToken.scaledBalanceOf(address(this)) - sharesBefore;

334:         _aTokenShares = _aTokenShares + aaveAToken.scaledBalanceOf(address(this)) - sharesBefore;

```

```solidity
File: contracts/common/circuitBreaker/OrigamiCircuitBreakerAllUsersPerPeriod.sol

5: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

5: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

6: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

6: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

6: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

7: import { IOrigamiCircuitBreaker } from "contracts/interfaces/common/circuitBreaker/IOrigamiCircuitBreaker.sol";

7: import { IOrigamiCircuitBreaker } from "contracts/interfaces/common/circuitBreaker/IOrigamiCircuitBreaker.sol";

7: import { IOrigamiCircuitBreaker } from "contracts/interfaces/common/circuitBreaker/IOrigamiCircuitBreaker.sol";

7: import { IOrigamiCircuitBreaker } from "contracts/interfaces/common/circuitBreaker/IOrigamiCircuitBreaker.sol";

98:     function preCheck(address /*onBehalfOf*/, uint256 amount) external override onlyProxy {

98:     function preCheck(address /*onBehalfOf*/, uint256 amount) external override onlyProxy {

98:     function preCheck(address /*onBehalfOf*/, uint256 amount) external override onlyProxy {

98:     function preCheck(address /*onBehalfOf*/, uint256 amount) external override onlyProxy {

99:         uint32 _nextBucketIndex = uint32(block.timestamp / secondsPerBucket);

109:                 for (; _minBucketResetIndex < _nextBucketIndex; ++_minBucketResetIndex) {

109:                 for (; _minBucketResetIndex < _nextBucketIndex; ++_minBucketResetIndex) {

111:                     buckets[(_minBucketResetIndex+1) % _nBuckets] = 1;

118:         uint256 _newUtilisation = _currentUtilisation(_nBuckets) + amount;

124:             buckets[_nextBucketIndex % _nBuckets] += amount;

151:             uint32 _oneperiodDurationAgoIndex = _nextBucketIndex - _nBuckets;

160:         uint32 _nextBucketIndex = uint32(block.timestamp / secondsPerBucket);

171:                 for (; _minBucketResetIndex < _nextBucketIndex; ++_minBucketResetIndex) {

171:                 for (; _minBucketResetIndex < _nextBucketIndex; ++_minBucketResetIndex) {

172:                     utilisation -= buckets[(_minBucketResetIndex+1) % _nBuckets] - 1;

172:                     utilisation -= buckets[(_minBucketResetIndex+1) % _nBuckets] - 1;

172:                     utilisation -= buckets[(_minBucketResetIndex+1) % _nBuckets] - 1;

183:             for (uint256 i; i < _nBuckets; ++i) {

183:             for (uint256 i; i < _nBuckets; ++i) {

184:                 amount += buckets[i];

188:             amount -= _nBuckets;

199:         secondsPerBucket = _periodDuration / _nBuckets;

206:             for (uint256 i = 0; i < _nBuckets; ++i) {

206:             for (uint256 i = 0; i < _nBuckets; ++i) {

```

```solidity
File: contracts/common/circuitBreaker/OrigamiCircuitBreakerProxy.sol

5: import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

5: import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

5: import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

5: import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

6: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

6: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

7: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

7: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

7: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

8: import { IOrigamiCircuitBreaker } from "contracts/interfaces/common/circuitBreaker/IOrigamiCircuitBreaker.sol";

8: import { IOrigamiCircuitBreaker } from "contracts/interfaces/common/circuitBreaker/IOrigamiCircuitBreaker.sol";

8: import { IOrigamiCircuitBreaker } from "contracts/interfaces/common/circuitBreaker/IOrigamiCircuitBreaker.sol";

8: import { IOrigamiCircuitBreaker } from "contracts/interfaces/common/circuitBreaker/IOrigamiCircuitBreaker.sol";

9: import { IOrigamiCircuitBreakerProxy } from "contracts/interfaces/common/circuitBreaker/IOrigamiCircuitBreakerProxy.sol";

9: import { IOrigamiCircuitBreakerProxy } from "contracts/interfaces/common/circuitBreaker/IOrigamiCircuitBreakerProxy.sol";

9: import { IOrigamiCircuitBreakerProxy } from "contracts/interfaces/common/circuitBreaker/IOrigamiCircuitBreakerProxy.sol";

9: import { IOrigamiCircuitBreakerProxy } from "contracts/interfaces/common/circuitBreaker/IOrigamiCircuitBreakerProxy.sol";

```

```solidity
File: contracts/common/flashLoan/OrigamiAaveV3FlashLoanProvider.sol

5: import { IPoolAddressesProvider } from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";

5: import { IPoolAddressesProvider } from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";

5: import { IPoolAddressesProvider } from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";

5: import { IPoolAddressesProvider } from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";

5: import { IPoolAddressesProvider } from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";

6: import { IPool } from "@aave/core-v3/contracts/interfaces/IPool.sol";

6: import { IPool } from "@aave/core-v3/contracts/interfaces/IPool.sol";

6: import { IPool } from "@aave/core-v3/contracts/interfaces/IPool.sol";

6: import { IPool } from "@aave/core-v3/contracts/interfaces/IPool.sol";

6: import { IPool } from "@aave/core-v3/contracts/interfaces/IPool.sol";

7: import { IFlashLoanReceiver } from "@aave/core-v3/contracts/flashloan/interfaces/IFlashLoanReceiver.sol";

7: import { IFlashLoanReceiver } from "@aave/core-v3/contracts/flashloan/interfaces/IFlashLoanReceiver.sol";

7: import { IFlashLoanReceiver } from "@aave/core-v3/contracts/flashloan/interfaces/IFlashLoanReceiver.sol";

7: import { IFlashLoanReceiver } from "@aave/core-v3/contracts/flashloan/interfaces/IFlashLoanReceiver.sol";

7: import { IFlashLoanReceiver } from "@aave/core-v3/contracts/flashloan/interfaces/IFlashLoanReceiver.sol";

7: import { IFlashLoanReceiver } from "@aave/core-v3/contracts/flashloan/interfaces/IFlashLoanReceiver.sol";

8: import { DataTypes } from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";

8: import { DataTypes } from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";

8: import { DataTypes } from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";

8: import { DataTypes } from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";

8: import { DataTypes } from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";

8: import { DataTypes } from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";

8: import { DataTypes } from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";

10: import { IOrigamiFlashLoanProvider } from "contracts/interfaces/common/flashLoan/IOrigamiFlashLoanProvider.sol";

10: import { IOrigamiFlashLoanProvider } from "contracts/interfaces/common/flashLoan/IOrigamiFlashLoanProvider.sol";

10: import { IOrigamiFlashLoanProvider } from "contracts/interfaces/common/flashLoan/IOrigamiFlashLoanProvider.sol";

10: import { IOrigamiFlashLoanProvider } from "contracts/interfaces/common/flashLoan/IOrigamiFlashLoanProvider.sol";

11: import { IOrigamiFlashLoanReceiver } from "contracts/interfaces/common/flashLoan/IOrigamiFlashLoanReceiver.sol";

11: import { IOrigamiFlashLoanReceiver } from "contracts/interfaces/common/flashLoan/IOrigamiFlashLoanReceiver.sol";

11: import { IOrigamiFlashLoanReceiver } from "contracts/interfaces/common/flashLoan/IOrigamiFlashLoanReceiver.sol";

11: import { IOrigamiFlashLoanReceiver } from "contracts/interfaces/common/flashLoan/IOrigamiFlashLoanReceiver.sol";

12: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

12: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

12: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

12: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

13: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

13: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

13: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

13: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

13: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

14: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

14: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

104:             _asset.forceApprove(address(POOL), _flAmount + _flFees);

```

```solidity
File: contracts/common/interestRate/BaseInterestRateModel.sol

5: import { IInterestRateModel } from "contracts/interfaces/common/interestRate/IInterestRateModel.sol";

5: import { IInterestRateModel } from "contracts/interfaces/common/interestRate/IInterestRateModel.sol";

5: import { IInterestRateModel } from "contracts/interfaces/common/interestRate/IInterestRateModel.sol";

5: import { IInterestRateModel } from "contracts/interfaces/common/interestRate/IInterestRateModel.sol";

14:     uint96 internal constant MAX_ALLOWED_INTEREST_RATE = 5e18; // 500% APR

14:     uint96 internal constant MAX_ALLOWED_INTEREST_RATE = 5e18; // 500% APR

```

```solidity
File: contracts/common/interestRate/LinearWithKinkInterestRateModel.sol

5: import { BaseInterestRateModel } from "contracts/common/interestRate/BaseInterestRateModel.sol";

5: import { BaseInterestRateModel } from "contracts/common/interestRate/BaseInterestRateModel.sol";

5: import { BaseInterestRateModel } from "contracts/common/interestRate/BaseInterestRateModel.sol";

6: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

6: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

6: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

7: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

7: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

8: import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

8: import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

118:                 utilizationRatio - _rateParams.kinkUtilizationRatio,

119:                 _rateParams.maxInterestRate - _rateParams.kinkInterestRate,

120:                 PRECISION - _rateParams.kinkUtilizationRatio,

122:             ) + _rateParams.kinkInterestRate;

127:                 _rateParams.kinkInterestRate - _rateParams.baseInterestRate,

130:             ) + _rateParams.baseInterestRate;

```

```solidity
File: contracts/common/oracle/OrigamiCrossRateOracle.sol

5: import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

5: import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

5: import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

5: import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

6: import { OrigamiOracleBase } from "contracts/common/oracle/OrigamiOracleBase.sol";

6: import { OrigamiOracleBase } from "contracts/common/oracle/OrigamiOracleBase.sol";

6: import { OrigamiOracleBase } from "contracts/common/oracle/OrigamiOracleBase.sol";

7: import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

7: import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

```

```solidity
File: contracts/common/oracle/OrigamiOracleBase.sol

5: import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

5: import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

5: import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

5: import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

6: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

6: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

7: import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

7: import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

57:         if (_quoteAssetDecimals > decimals + _baseAssetDecimals) revert CommonEventsAndErrors.InvalidParam();

58:         assetScalingFactor = 10 ** (decimals + _baseAssetDecimals - _quoteAssetDecimals);

58:         assetScalingFactor = 10 ** (decimals + _baseAssetDecimals - _quoteAssetDecimals);

58:         assetScalingFactor = 10 ** (decimals + _baseAssetDecimals - _quoteAssetDecimals);

58:         assetScalingFactor = 10 ** (decimals + _baseAssetDecimals - _quoteAssetDecimals);

81:         uint256 /*price1*/, 

81:         uint256 /*price1*/, 

81:         uint256 /*price1*/, 

81:         uint256 /*price1*/, 

82:         uint256 /*price2*/, 

82:         uint256 /*price2*/, 

82:         uint256 /*price2*/, 

82:         uint256 /*price2*/, 

83:         address /*baseAsset*/,

83:         address /*baseAsset*/,

83:         address /*baseAsset*/,

83:         address /*baseAsset*/,

84:         address /*quoteAsset*/

84:         address /*quoteAsset*/

84:         address /*quoteAsset*/

84:         address /*quoteAsset*/

```

```solidity
File: contracts/common/oracle/OrigamiStableChainlinkOracle.sol

5: import { IAggregatorV3Interface } from "contracts/interfaces/external/chainlink/IAggregatorV3Interface.sol";

5: import { IAggregatorV3Interface } from "contracts/interfaces/external/chainlink/IAggregatorV3Interface.sol";

5: import { IAggregatorV3Interface } from "contracts/interfaces/external/chainlink/IAggregatorV3Interface.sol";

5: import { IAggregatorV3Interface } from "contracts/interfaces/external/chainlink/IAggregatorV3Interface.sol";

6: import { OrigamiOracleBase } from "contracts/common/oracle/OrigamiOracleBase.sol";

6: import { OrigamiOracleBase } from "contracts/common/oracle/OrigamiOracleBase.sol";

6: import { OrigamiOracleBase } from "contracts/common/oracle/OrigamiOracleBase.sol";

7: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

7: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

7: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

8: import { Range } from "contracts/libraries/Range.sol";

8: import { Range } from "contracts/libraries/Range.sol";

9: import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

9: import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

10: import { Chainlink } from "contracts/libraries/Chainlink.sol";

10: import { Chainlink } from "contracts/libraries/Chainlink.sol";

```

```solidity
File: contracts/common/oracle/OrigamiWstEthToEthOracle.sol

5: import { IStETH } from "contracts/interfaces/external/lido/IStETH.sol";

5: import { IStETH } from "contracts/interfaces/external/lido/IStETH.sol";

5: import { IStETH } from "contracts/interfaces/external/lido/IStETH.sol";

5: import { IStETH } from "contracts/interfaces/external/lido/IStETH.sol";

6: import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

6: import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

6: import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

6: import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

7: import { OrigamiOracleBase } from "contracts/common/oracle/OrigamiOracleBase.sol";

7: import { OrigamiOracleBase } from "contracts/common/oracle/OrigamiOracleBase.sol";

7: import { OrigamiOracleBase } from "contracts/common/oracle/OrigamiOracleBase.sol";

8: import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

8: import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

```

```solidity
File: contracts/common/swappers/OrigamiDexAggregatorSwapper.sol

5: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

5: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

5: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

5: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

6: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

6: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

6: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

6: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

6: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

8: import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";

8: import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";

8: import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";

8: import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";

9: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

9: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

9: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

10: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

10: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

99:             buyTokenAmount = current.buyTokenAmount - initial.buyTokenAmount;

```

```solidity
File: contracts/investments/OrigamiInvestment.sol

5: import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";

5: import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";

5: import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";

6: import { MintableToken } from "contracts/common/MintableToken.sol";

6: import { MintableToken } from "contracts/common/MintableToken.sol";

7: import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

7: import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

7: import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

```

```solidity
File: contracts/investments/OrigamiInvestmentVault.sol

5: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

5: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

5: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

5: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

5: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

6: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

6: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

6: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

6: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

7: import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

7: import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

7: import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

9: import { IOrigamiInvestmentVault } from "contracts/interfaces/investments/IOrigamiInvestmentVault.sol";

9: import { IOrigamiInvestmentVault } from "contracts/interfaces/investments/IOrigamiInvestmentVault.sol";

9: import { IOrigamiInvestmentVault } from "contracts/interfaces/investments/IOrigamiInvestmentVault.sol";

10: import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";

10: import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";

10: import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";

11: import { ITokenPrices } from "contracts/interfaces/common/ITokenPrices.sol";

11: import { ITokenPrices } from "contracts/interfaces/common/ITokenPrices.sol";

11: import { ITokenPrices } from "contracts/interfaces/common/ITokenPrices.sol";

12: import { RepricingToken } from "contracts/common/RepricingToken.sol";

12: import { RepricingToken } from "contracts/common/RepricingToken.sol";

13: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

13: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

14: import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

14: import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

15: import { Whitelisted } from "contracts/common/access/Whitelisted.sol";

15: import { Whitelisted } from "contracts/common/access/Whitelisted.sol";

15: import { Whitelisted } from "contracts/common/access/Whitelisted.sol";

107:         newItems = new address[](items.length+1);

111:         for (; i < _length; ++i) {

111:         for (; i < _length; ++i) {

```

```solidity
File: contracts/investments/OrigamiOToken.sol

5: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

5: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

5: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

5: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

5: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

6: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

6: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

6: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

6: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

8: import { IOrigamiOToken } from "contracts/interfaces/investments/IOrigamiOToken.sol";

8: import { IOrigamiOToken } from "contracts/interfaces/investments/IOrigamiOToken.sol";

8: import { IOrigamiOToken } from "contracts/interfaces/investments/IOrigamiOToken.sol";

9: import { IOrigamiOTokenManager } from "contracts/interfaces/investments/IOrigamiOTokenManager.sol";

9: import { IOrigamiOTokenManager } from "contracts/interfaces/investments/IOrigamiOTokenManager.sol";

9: import { IOrigamiOTokenManager } from "contracts/interfaces/investments/IOrigamiOTokenManager.sol";

10: import { OrigamiInvestment } from "contracts/investments/OrigamiInvestment.sol";

10: import { OrigamiInvestment } from "contracts/investments/OrigamiInvestment.sol";

11: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

11: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

55:         amoMinted += _amount;

68:             amoMinted = _amoMinted - _amount;

131:         InvestQuoteData calldata /*quoteData*/

131:         InvestQuoteData calldata /*quoteData*/

131:         InvestQuoteData calldata /*quoteData*/

131:         InvestQuoteData calldata /*quoteData*/

140:         ExitQuoteData calldata /*quoteData*/, address payable /*recipient*/

140:         ExitQuoteData calldata /*quoteData*/, address payable /*recipient*/

140:         ExitQuoteData calldata /*quoteData*/, address payable /*recipient*/

140:         ExitQuoteData calldata /*quoteData*/, address payable /*recipient*/

140:         ExitQuoteData calldata /*quoteData*/, address payable /*recipient*/

140:         ExitQuoteData calldata /*quoteData*/, address payable /*recipient*/

140:         ExitQuoteData calldata /*quoteData*/, address payable /*recipient*/

140:         ExitQuoteData calldata /*quoteData*/, address payable /*recipient*/

141:     ) external virtual override returns (uint256 /*nativeAmount*/) {

141:     ) external virtual override returns (uint256 /*nativeAmount*/) {

141:     ) external virtual override returns (uint256 /*nativeAmount*/) {

141:     ) external virtual override returns (uint256 /*nativeAmount*/) {

227:             return totalSupply() - amoMinted;

```

```solidity
File: contracts/investments/lending/OrigamiDebtToken.sol

5: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

5: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

5: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

5: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

5: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

6: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

6: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

6: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

6: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

6: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

8: import { IOrigamiDebtToken } from "contracts/interfaces/investments/lending/IOrigamiDebtToken.sol";

8: import { IOrigamiDebtToken } from "contracts/interfaces/investments/lending/IOrigamiDebtToken.sol";

8: import { IOrigamiDebtToken } from "contracts/interfaces/investments/lending/IOrigamiDebtToken.sol";

8: import { IOrigamiDebtToken } from "contracts/interfaces/investments/lending/IOrigamiDebtToken.sol";

9: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

9: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

10: import { CompoundedInterest } from "contracts/libraries/CompoundedInterest.sol";

10: import { CompoundedInterest } from "contracts/libraries/CompoundedInterest.sol";

11: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

11: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

11: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

12: import { SafeCast } from "contracts/libraries/SafeCast.sol";

12: import { SafeCast } from "contracts/libraries/SafeCast.sol";

68:     uint96 private constant MAX_INTEREST_RATE = 10e18; // 1_000%

68:     uint96 private constant MAX_INTEREST_RATE = 10e18; // 1_000%

170:         address /*owner*/,

170:         address /*owner*/,

170:         address /*owner*/,

170:         address /*owner*/,

171:         address /*spender*/

171:         address /*spender*/

171:         address /*spender*/

171:         address /*spender*/

180:         address /*spender*/,

180:         address /*spender*/,

180:         address /*spender*/,

180:         address /*spender*/,

181:         uint256 /*amount*/

181:         uint256 /*amount*/

181:         uint256 /*amount*/

181:         uint256 /*amount*/

229:         for (uint256 i; i < _length; ++i) {

229:         for (uint256 i; i < _length; ++i) {

234:             _interestDelta += _debtorPosition.interestDelta;

239:         estimatedTotalInterest += _interestDelta;

252:         for (uint256 i; i < _length; ++i) {

252:         for (uint256 i; i < _length; ++i) {

284:             return uint256(totalPrincipal) + estimatedTotalInterest;

293:         return repaidTotalInterest + estimatedTotalInterest;

303:         for (uint256 i; i < _length; ++i) {

303:         for (uint256 i; i < _length; ++i) {

306:                 _excludeSum += _debtor.principal + _debtor.interestCheckpoint;

306:                 _excludeSum += _debtor.principal + _debtor.interestCheckpoint;

311:             return uint256(totalPrincipal) + estimatedTotalInterest - _excludeSum;

311:             return uint256(totalPrincipal) + estimatedTotalInterest - _excludeSum;

323:         return debtorPosition.principal + debtorPosition.interest;

349:             totalPrincipal += _amount;

350:             toDebtor.principal = _debtorPosition.principal = _debtorPosition.principal + _amount;

392:             _burnAmount -= _interestDebtRepaid;

397:             _debtor.principal = _debtorPosition.principal = _debtorPosition.principal - _burnAmount;

398:             _debtor.interestCheckpoint = _debtorPosition.interest = _debtorPosition.interest - _interestDebtRepaid;

401:             totalPrincipal -= _burnAmount;

406:                 uint128 totalInterest = estimatedTotalInterest + _debtorPosition.interestDelta;

407:                 estimatedTotalInterest = totalInterest > _interestDebtRepaid ? totalInterest - _interestDebtRepaid : 0;

410:             repaidTotalInterest += _interestDebtRepaid;

428:             _timeElapsed = uint32(block.timestamp) - _debtor.timeCheckpoint;

439:                     _debtorTotalDue = uint256(_debtorPosition.principal) + _debtorPosition.interest;

447:                     uint128 _newInterest = _debtorTotalDue.encodeUInt128() - _debtorPosition.principal;

448:                     _debtorPosition.interestDelta = _newInterest - _debtorPosition.interest;

464:                estimatedTotalInterest += debtorPosition.interestDelta;

```

```solidity
File: contracts/investments/lending/OrigamiLendingClerk.sol

5: import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

5: import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

5: import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

5: import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

5: import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

6: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

6: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

6: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

6: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

6: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

7: import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

7: import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

7: import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

7: import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

9: import { IOrigamiCircuitBreakerProxy } from "contracts/interfaces/common/circuitBreaker/IOrigamiCircuitBreakerProxy.sol";

9: import { IOrigamiCircuitBreakerProxy } from "contracts/interfaces/common/circuitBreaker/IOrigamiCircuitBreakerProxy.sol";

9: import { IOrigamiCircuitBreakerProxy } from "contracts/interfaces/common/circuitBreaker/IOrigamiCircuitBreakerProxy.sol";

9: import { IOrigamiCircuitBreakerProxy } from "contracts/interfaces/common/circuitBreaker/IOrigamiCircuitBreakerProxy.sol";

10: import { IInterestRateModel } from "contracts/interfaces/common/interestRate/IInterestRateModel.sol";

10: import { IInterestRateModel } from "contracts/interfaces/common/interestRate/IInterestRateModel.sol";

10: import { IInterestRateModel } from "contracts/interfaces/common/interestRate/IInterestRateModel.sol";

10: import { IInterestRateModel } from "contracts/interfaces/common/interestRate/IInterestRateModel.sol";

11: import { IOrigamiOToken } from "contracts/interfaces/investments/IOrigamiOToken.sol";

11: import { IOrigamiOToken } from "contracts/interfaces/investments/IOrigamiOToken.sol";

11: import { IOrigamiOToken } from "contracts/interfaces/investments/IOrigamiOToken.sol";

12: import { IOrigamiLendingClerk } from "contracts/interfaces/investments/lending/IOrigamiLendingClerk.sol";

12: import { IOrigamiLendingClerk } from "contracts/interfaces/investments/lending/IOrigamiLendingClerk.sol";

12: import { IOrigamiLendingClerk } from "contracts/interfaces/investments/lending/IOrigamiLendingClerk.sol";

12: import { IOrigamiLendingClerk } from "contracts/interfaces/investments/lending/IOrigamiLendingClerk.sol";

13: import { IOrigamiIdleStrategyManager } from "contracts/interfaces/investments/lending/idleStrategy/IOrigamiIdleStrategyManager.sol";

13: import { IOrigamiIdleStrategyManager } from "contracts/interfaces/investments/lending/idleStrategy/IOrigamiIdleStrategyManager.sol";

13: import { IOrigamiIdleStrategyManager } from "contracts/interfaces/investments/lending/idleStrategy/IOrigamiIdleStrategyManager.sol";

13: import { IOrigamiIdleStrategyManager } from "contracts/interfaces/investments/lending/idleStrategy/IOrigamiIdleStrategyManager.sol";

13: import { IOrigamiIdleStrategyManager } from "contracts/interfaces/investments/lending/idleStrategy/IOrigamiIdleStrategyManager.sol";

14: import { IOrigamiDebtToken } from "contracts/interfaces/investments/lending/IOrigamiDebtToken.sol";

14: import { IOrigamiDebtToken } from "contracts/interfaces/investments/lending/IOrigamiDebtToken.sol";

14: import { IOrigamiDebtToken } from "contracts/interfaces/investments/lending/IOrigamiDebtToken.sol";

14: import { IOrigamiDebtToken } from "contracts/interfaces/investments/lending/IOrigamiDebtToken.sol";

15: import { IOrigamiLendingBorrower } from "contracts/interfaces/investments/lending/IOrigamiLendingBorrower.sol";

15: import { IOrigamiLendingBorrower } from "contracts/interfaces/investments/lending/IOrigamiLendingBorrower.sol";

15: import { IOrigamiLendingBorrower } from "contracts/interfaces/investments/lending/IOrigamiLendingBorrower.sol";

15: import { IOrigamiLendingBorrower } from "contracts/interfaces/investments/lending/IOrigamiLendingBorrower.sol";

16: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

16: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

17: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

17: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

17: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

18: import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

18: import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

124:             _assetScalar = 10 ** (_origamiDecimals - _assetDecimals);

124:             _assetScalar = 10 ** (_origamiDecimals - _assetDecimals);

124:             _assetScalar = 10 ** (_origamiDecimals - _assetDecimals);

285:             uint256 _debtTokenHoldersLength = _length + 1;

286:             address[] memory _debtTokenHolders = new address[](_length+1);

288:             for (; i < _debtTokenHoldersLength; ++i) {

288:             for (; i < _debtTokenHoldersLength; ++i) {

289:                 _debtTokenHolders[i] = borrowerList[i-1];

299:             for (i=0; i < _length; ++i) {

299:             for (i=0; i < _length; ++i) {

318:                             DEPOSIT/WITHDRAW

366:                              BORROW/REPAY

410:         uint256 _debtBalance = debtToken.balanceOf(borrower);     // 18 dp

410:         uint256 _debtBalance = debtToken.balanceOf(borrower);     // 18 dp

411:         uint256 _maxRepayAmount = _debtBalance.scaleDown(_assetScalar, OrigamiMath.Rounding.ROUND_UP);   // asset's dp

411:         uint256 _maxRepayAmount = _debtBalance.scaleDown(_assetScalar, OrigamiMath.Rounding.ROUND_UP);   // asset's dp

414:         uint256 _debtToTransfer;  // 18 dp

414:         uint256 _debtToTransfer;  // 18 dp

507:         uint256 _globalAvailable = _globalAvailableToBorrow();                       // asset's dp

507:         uint256 _globalAvailable = _globalAvailableToBorrow();                       // asset's dp

508:         uint256 _idleStrategyAvailable = idleStrategyManager.availableToWithdraw();  // asset's dp

508:         uint256 _idleStrategyAvailable = idleStrategyManager.availableToWithdraw();  // asset's dp

552:         uint256 _totalBorrowerDebt = totalBorrowerDebt();           // debt in 18dp

552:         uint256 _totalBorrowerDebt = totalBorrowerDebt();           // debt in 18dp

553:         uint256 _totalBorrowerCeiling = oToken.circulatingSupply(); // oToken in 18dp

553:         uint256 _totalBorrowerCeiling = oToken.circulatingSupply(); // oToken in 18dp

681:         uint256 _totalBorrowerDebt = totalBorrowerDebt();           // debt in 18dp

681:         uint256 _totalBorrowerDebt = totalBorrowerDebt();           // debt in 18dp

682:         uint256 _totalBorrowerCeiling = oToken.circulatingSupply(); // oToken in 18dp

682:         uint256 _totalBorrowerCeiling = oToken.circulatingSupply(); // oToken in 18dp

686:             ? (_totalBorrowerCeiling - _totalBorrowerDebt).scaleDown(_assetScalar, OrigamiMath.Rounding.ROUND_DOWN)

701:         uint256 _borrowerAmount;   // asset's dp

701:         uint256 _borrowerAmount;   // asset's dp

704:             uint256 _borrowerDebtBalance = debtToken.balanceOf(borrower); // 18dp

704:             uint256 _borrowerDebtBalance = debtToken.balanceOf(borrower); // 18dp

705:             uint256 _borrowerDebtCeiling = borrowerConfig.debtCeiling;      // 18 dp

705:             uint256 _borrowerDebtCeiling = borrowerConfig.debtCeiling;      // 18 dp

709:                     ? (_borrowerDebtCeiling - _borrowerDebtBalance).scaleDown(_assetScalar, OrigamiMath.Rounding.ROUND_DOWN)

714:         uint256 _globalAmount = totalAvailableToWithdraw(); // asset's dp

714:         uint256 _globalAmount = totalAvailableToWithdraw(); // asset's dp

797:         uint256 _borrowerDebtBalance = debtToken.balanceOf(borrower); // 18dp

797:         uint256 _borrowerDebtBalance = debtToken.balanceOf(borrower); // 18dp

798:         uint256 _borrowerDebtCeiling = borrowerConfig.debtCeiling;      // 18 dp

798:         uint256 _borrowerDebtCeiling = borrowerConfig.debtCeiling;      // 18 dp

```

```solidity
File: contracts/investments/lending/OrigamiLendingRewardsMinter.sol

5: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

5: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

5: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

5: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

6: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

6: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

6: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

6: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

6: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

8: import { IMintableToken } from "contracts/interfaces/common/IMintableToken.sol";

8: import { IMintableToken } from "contracts/interfaces/common/IMintableToken.sol";

8: import { IMintableToken } from "contracts/interfaces/common/IMintableToken.sol";

9: import { IOrigamiInvestmentVault } from "contracts/interfaces/investments/IOrigamiInvestmentVault.sol";

9: import { IOrigamiInvestmentVault } from "contracts/interfaces/investments/IOrigamiInvestmentVault.sol";

9: import { IOrigamiInvestmentVault } from "contracts/interfaces/investments/IOrigamiInvestmentVault.sol";

10: import { IOrigamiDebtToken } from "contracts/interfaces/investments/lending/IOrigamiDebtToken.sol";

10: import { IOrigamiDebtToken } from "contracts/interfaces/investments/lending/IOrigamiDebtToken.sol";

10: import { IOrigamiDebtToken } from "contracts/interfaces/investments/lending/IOrigamiDebtToken.sol";

10: import { IOrigamiDebtToken } from "contracts/interfaces/investments/lending/IOrigamiDebtToken.sol";

11: import { IOrigamiLendingRewardsMinter } from "contracts/interfaces/investments/lending/IOrigamiLendingRewardsMinter.sol";

11: import { IOrigamiLendingRewardsMinter } from "contracts/interfaces/investments/lending/IOrigamiLendingRewardsMinter.sol";

11: import { IOrigamiLendingRewardsMinter } from "contracts/interfaces/investments/lending/IOrigamiLendingRewardsMinter.sol";

11: import { IOrigamiLendingRewardsMinter } from "contracts/interfaces/investments/lending/IOrigamiLendingRewardsMinter.sol";

12: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

12: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

13: import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

13: import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

14: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

14: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

14: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

122:         uint256 mintAmount = (debtToken.estimatedCumulativeInterest() - _cumulativeInterestCheckpoint).subtractBps(carryOverRate);

129:             cumulativeInterestCheckpoint = _cumulativeInterestCheckpoint + mintAmount;

```

```solidity
File: contracts/investments/lending/OrigamiLendingSupplyManager.sol

5: import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

5: import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

5: import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

5: import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

5: import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

6: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

6: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

6: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

6: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

6: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

7: import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

7: import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

7: import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

7: import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

9: import { IOrigamiCircuitBreakerProxy } from "contracts/interfaces/common/circuitBreaker/IOrigamiCircuitBreakerProxy.sol";

9: import { IOrigamiCircuitBreakerProxy } from "contracts/interfaces/common/circuitBreaker/IOrigamiCircuitBreakerProxy.sol";

9: import { IOrigamiCircuitBreakerProxy } from "contracts/interfaces/common/circuitBreaker/IOrigamiCircuitBreakerProxy.sol";

9: import { IOrigamiCircuitBreakerProxy } from "contracts/interfaces/common/circuitBreaker/IOrigamiCircuitBreakerProxy.sol";

10: import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";

10: import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";

10: import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";

11: import { IOrigamiLendingSupplyManager } from "contracts/interfaces/investments/lending/IOrigamiLendingSupplyManager.sol";

11: import { IOrigamiLendingSupplyManager } from "contracts/interfaces/investments/lending/IOrigamiLendingSupplyManager.sol";

11: import { IOrigamiLendingSupplyManager } from "contracts/interfaces/investments/lending/IOrigamiLendingSupplyManager.sol";

11: import { IOrigamiLendingSupplyManager } from "contracts/interfaces/investments/lending/IOrigamiLendingSupplyManager.sol";

12: import { IOrigamiLendingClerk } from "contracts/interfaces/investments/lending/IOrigamiLendingClerk.sol";

12: import { IOrigamiLendingClerk } from "contracts/interfaces/investments/lending/IOrigamiLendingClerk.sol";

12: import { IOrigamiLendingClerk } from "contracts/interfaces/investments/lending/IOrigamiLendingClerk.sol";

12: import { IOrigamiLendingClerk } from "contracts/interfaces/investments/lending/IOrigamiLendingClerk.sol";

13: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

13: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

14: import { Whitelisted } from "contracts/common/access/Whitelisted.sol";

14: import { Whitelisted } from "contracts/common/access/Whitelisted.sol";

14: import { Whitelisted } from "contracts/common/access/Whitelisted.sol";

15: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

15: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

15: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

16: import { OrigamiManagerPausable } from "contracts/investments/util/OrigamiManagerPausable.sol";

16: import { OrigamiManagerPausable } from "contracts/investments/util/OrigamiManagerPausable.sol";

16: import { OrigamiManagerPausable } from "contracts/investments/util/OrigamiManagerPausable.sol";

17: import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

17: import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

78:             _assetScalar = 10 ** (_origamiDecimals - _assetDecimals);

78:             _assetScalar = 10 ** (_origamiDecimals - _assetDecimals);

78:             _assetScalar = 10 ** (_origamiDecimals - _assetDecimals);

242:             underlyingInvestmentQuoteData: "" // No extra underlyingInvestmentQuoteData

242:             underlyingInvestmentQuoteData: "" // No extra underlyingInvestmentQuoteData

```

```solidity
File: contracts/investments/lending/idleStrategy/OrigamiAaveV3IdleStrategy.sol

5: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

5: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

5: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

5: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

6: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

6: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

6: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

6: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

6: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

7: import { IPoolAddressesProvider } from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";

7: import { IPoolAddressesProvider } from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";

7: import { IPoolAddressesProvider } from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";

7: import { IPoolAddressesProvider } from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";

7: import { IPoolAddressesProvider } from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";

8: import { IPool } from "@aave/core-v3/contracts/interfaces/IPool.sol";

8: import { IPool } from "@aave/core-v3/contracts/interfaces/IPool.sol";

8: import { IPool } from "@aave/core-v3/contracts/interfaces/IPool.sol";

8: import { IPool } from "@aave/core-v3/contracts/interfaces/IPool.sol";

8: import { IPool } from "@aave/core-v3/contracts/interfaces/IPool.sol";

10: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

10: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

11: import { OrigamiAbstractIdleStrategy } from "contracts/investments/lending/idleStrategy/OrigamiAbstractIdleStrategy.sol";

11: import { OrigamiAbstractIdleStrategy } from "contracts/investments/lending/idleStrategy/OrigamiAbstractIdleStrategy.sol";

11: import { OrigamiAbstractIdleStrategy } from "contracts/investments/lending/idleStrategy/OrigamiAbstractIdleStrategy.sol";

11: import { OrigamiAbstractIdleStrategy } from "contracts/investments/lending/idleStrategy/OrigamiAbstractIdleStrategy.sol";

50:         lendingPool.supply(address(asset), amount, address(this), 0 /* no referralCode */);

50:         lendingPool.supply(address(asset), amount, address(this), 0 /* no referralCode */);

50:         lendingPool.supply(address(asset), amount, address(this), 0 /* no referralCode */);

50:         lendingPool.supply(address(asset), amount, address(this), 0 /* no referralCode */);

```

```solidity
File: contracts/investments/lending/idleStrategy/OrigamiAbstractIdleStrategy.sol

5: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

5: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

5: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

5: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

7: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

7: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

7: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

8: import { IOrigamiIdleStrategy } from "contracts/interfaces/investments/lending/idleStrategy/IOrigamiIdleStrategy.sol";

8: import { IOrigamiIdleStrategy } from "contracts/interfaces/investments/lending/idleStrategy/IOrigamiIdleStrategy.sol";

8: import { IOrigamiIdleStrategy } from "contracts/interfaces/investments/lending/idleStrategy/IOrigamiIdleStrategy.sol";

8: import { IOrigamiIdleStrategy } from "contracts/interfaces/investments/lending/idleStrategy/IOrigamiIdleStrategy.sol";

8: import { IOrigamiIdleStrategy } from "contracts/interfaces/investments/lending/idleStrategy/IOrigamiIdleStrategy.sol";

```

```solidity
File: contracts/investments/lending/idleStrategy/OrigamiIdleStrategyManager.sol

5: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

5: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

5: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

5: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

6: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

6: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

6: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

6: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

6: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

8: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

8: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

9: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

9: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

9: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

10: import { IOrigamiIdleStrategyManager } from "contracts/interfaces/investments/lending/idleStrategy/IOrigamiIdleStrategyManager.sol";

10: import { IOrigamiIdleStrategyManager } from "contracts/interfaces/investments/lending/idleStrategy/IOrigamiIdleStrategyManager.sol";

10: import { IOrigamiIdleStrategyManager } from "contracts/interfaces/investments/lending/idleStrategy/IOrigamiIdleStrategyManager.sol";

10: import { IOrigamiIdleStrategyManager } from "contracts/interfaces/investments/lending/idleStrategy/IOrigamiIdleStrategyManager.sol";

10: import { IOrigamiIdleStrategyManager } from "contracts/interfaces/investments/lending/idleStrategy/IOrigamiIdleStrategyManager.sol";

11: import { IOrigamiIdleStrategy } from "contracts/interfaces/investments/lending/idleStrategy/IOrigamiIdleStrategy.sol";

11: import { IOrigamiIdleStrategy } from "contracts/interfaces/investments/lending/idleStrategy/IOrigamiIdleStrategy.sol";

11: import { IOrigamiIdleStrategy } from "contracts/interfaces/investments/lending/idleStrategy/IOrigamiIdleStrategy.sol";

11: import { IOrigamiIdleStrategy } from "contracts/interfaces/investments/lending/idleStrategy/IOrigamiIdleStrategy.sol";

11: import { IOrigamiIdleStrategy } from "contracts/interfaces/investments/lending/idleStrategy/IOrigamiIdleStrategy.sol";

129:                     underlyingAllocation = _balance - _threshold;

155:                 withdrawnFromIdleStrategy = _balance > amount ? 0 : amount - _balance;

162:                 withdrawnFromIdleStrategy += withdrawalBuffer;

166:                 _balance += _idleStrategy.withdraw(withdrawnFromIdleStrategy, address(this));

215:             ? asset.balanceOf(address(this)) + _idleStrategy.availableToWithdraw()

232:             ? asset.balanceOf(address(this)) + _idleStrategy.totalBalance()

253:             ? asset.balanceOf(address(this)) + _idleStrategy.checkpointTotalBalance()

```

```solidity
File: contracts/investments/lovToken/OrigamiLovToken.sol

5: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

5: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

5: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

5: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

5: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

6: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

6: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

6: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

6: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

8: import { IOrigamiOTokenManager } from "contracts/interfaces/investments/IOrigamiOTokenManager.sol";

8: import { IOrigamiOTokenManager } from "contracts/interfaces/investments/IOrigamiOTokenManager.sol";

8: import { IOrigamiOTokenManager } from "contracts/interfaces/investments/IOrigamiOTokenManager.sol";

9: import { IOrigamiLovToken } from "contracts/interfaces/investments/lovToken/IOrigamiLovToken.sol";

9: import { IOrigamiLovToken } from "contracts/interfaces/investments/lovToken/IOrigamiLovToken.sol";

9: import { IOrigamiLovToken } from "contracts/interfaces/investments/lovToken/IOrigamiLovToken.sol";

9: import { IOrigamiLovToken } from "contracts/interfaces/investments/lovToken/IOrigamiLovToken.sol";

10: import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";

10: import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";

10: import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";

10: import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";

10: import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";

11: import { ITokenPrices } from "contracts/interfaces/common/ITokenPrices.sol";

11: import { ITokenPrices } from "contracts/interfaces/common/ITokenPrices.sol";

11: import { ITokenPrices } from "contracts/interfaces/common/ITokenPrices.sol";

12: import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

12: import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

12: import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

12: import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

14: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

14: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

15: import { OrigamiInvestment } from "contracts/investments/OrigamiInvestment.sol";

15: import { OrigamiInvestment } from "contracts/investments/OrigamiInvestment.sol";

16: import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

16: import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

173:         InvestQuoteData calldata /*quoteData*/

173:         InvestQuoteData calldata /*quoteData*/

173:         InvestQuoteData calldata /*quoteData*/

173:         InvestQuoteData calldata /*quoteData*/

183:         ExitQuoteData calldata /*quoteData*/, address payable /*recipient*/

183:         ExitQuoteData calldata /*quoteData*/, address payable /*recipient*/

183:         ExitQuoteData calldata /*quoteData*/, address payable /*recipient*/

183:         ExitQuoteData calldata /*quoteData*/, address payable /*recipient*/

183:         ExitQuoteData calldata /*quoteData*/, address payable /*recipient*/

183:         ExitQuoteData calldata /*quoteData*/, address payable /*recipient*/

183:         ExitQuoteData calldata /*quoteData*/, address payable /*recipient*/

183:         ExitQuoteData calldata /*quoteData*/, address payable /*recipient*/

184:     ) external virtual override returns (uint256 /*nativeAmount*/) {

184:     ) external virtual override returns (uint256 /*nativeAmount*/) {

184:     ) external virtual override returns (uint256 /*nativeAmount*/) {

184:     ) external virtual override returns (uint256 /*nativeAmount*/) {

192:         if (block.timestamp < (lastPerformanceFeeTime + PERFORMANCE_FEE_FREQUENCY)) revert TooSoon();

317:         return lovManager.sharesToReserves(10 ** decimals(), IOrigamiOracle.PriceType.HISTORIC_PRICE);

317:         return lovManager.sharesToReserves(10 ** decimals(), IOrigamiOracle.PriceType.HISTORIC_PRICE);

333:         uint256 /*assets*/,

333:         uint256 /*assets*/,

333:         uint256 /*assets*/,

333:         uint256 /*assets*/,

334:         uint256 /*liabilities*/,

334:         uint256 /*liabilities*/,

334:         uint256 /*liabilities*/,

334:         uint256 /*liabilities*/,

335:         uint256 /*ratio*/

335:         uint256 /*ratio*/

335:         uint256 /*ratio*/

335:         uint256 /*ratio*/

346:     function effectiveExposure() external override view returns (uint128 /*effectiveExposure*/) {

346:     function effectiveExposure() external override view returns (uint128 /*effectiveExposure*/) {

346:     function effectiveExposure() external override view returns (uint128 /*effectiveExposure*/) {

346:     function effectiveExposure() external override view returns (uint128 /*effectiveExposure*/) {

354:     function userALRange() external override view returns (uint128 /*floor*/, uint128 /*ceiling*/) {

354:     function userALRange() external override view returns (uint128 /*floor*/, uint128 /*ceiling*/) {

354:     function userALRange() external override view returns (uint128 /*floor*/, uint128 /*ceiling*/) {

354:     function userALRange() external override view returns (uint128 /*floor*/, uint128 /*ceiling*/) {

354:     function userALRange() external override view returns (uint128 /*floor*/, uint128 /*ceiling*/) {

354:     function userALRange() external override view returns (uint128 /*floor*/, uint128 /*ceiling*/) {

354:     function userALRange() external override view returns (uint128 /*floor*/, uint128 /*ceiling*/) {

354:     function userALRange() external override view returns (uint128 /*floor*/, uint128 /*ceiling*/) {

392:             performanceFee * PERFORMANCE_FEE_FREQUENCY, 

393:             OrigamiMath.BASIS_POINTS_DIVISOR * 365 days, 

```

```solidity
File: contracts/investments/lovToken/managers/OrigamiAbstractLovTokenManager.sol

5: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

5: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

5: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

5: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

6: import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

6: import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

6: import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

6: import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

6: import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

8: import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";

8: import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";

8: import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";

9: import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";

9: import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";

9: import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";

9: import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";

9: import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";

10: import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

10: import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

10: import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

10: import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

12: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

12: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

12: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

13: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

13: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

14: import { OrigamiManagerPausable } from "contracts/investments/util/OrigamiManagerPausable.sol";

14: import { OrigamiManagerPausable } from "contracts/investments/util/OrigamiManagerPausable.sol";

14: import { OrigamiManagerPausable } from "contracts/investments/util/OrigamiManagerPausable.sol";

15: import { Range } from "contracts/libraries/Range.sol";

15: import { Range } from "contracts/libraries/Range.sol";

16: import { Whitelisted } from "contracts/common/access/Whitelisted.sol";

16: import { Whitelisted } from "contracts/common/access/Whitelisted.sol";

16: import { Whitelisted } from "contracts/common/access/Whitelisted.sol";

17: import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

17: import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

139:         buffer += uint16(OrigamiMath.BASIS_POINTS_DIVISOR);

234:         address /*account*/,

234:         address /*account*/,

234:         address /*account*/,

234:         address /*account*/,

336:                     _remainingCapacity = _maxReserves - _currentReserves;

418:                 _amountFromAvailableCapacity = cache.assets - _minReserves;

500:         uint256 /*assets*/,

500:         uint256 /*assets*/,

500:         uint256 /*assets*/,

500:         uint256 /*assets*/,

501:         uint256 /*liabilities*/,

501:         uint256 /*liabilities*/,

501:         uint256 /*liabilities*/,

501:         uint256 /*liabilities*/,

502:         uint256 /*ratio*/

502:         uint256 /*ratio*/

502:         uint256 /*ratio*/

502:         uint256 /*ratio*/

523:                 redeemableReserves = cache.assets - cache.liabilities;

616:                 ? cache.assets - _liabilitiesWithBuffer

668:         return 10 ** (_sharesDecimals - _reservesDecimals);

668:         return 10 ** (_sharesDecimals - _reservesDecimals);

668:         return 10 ** (_sharesDecimals - _reservesDecimals);

```

```solidity
File: contracts/investments/lovToken/managers/OrigamiLovTokenErc4626Manager.sol

5: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

5: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

5: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

5: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

5: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

6: import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

6: import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

6: import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

6: import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

6: import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

7: import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

7: import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

7: import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

9: import { IOrigamiLovTokenErc4626Manager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenErc4626Manager.sol";

9: import { IOrigamiLovTokenErc4626Manager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenErc4626Manager.sol";

9: import { IOrigamiLovTokenErc4626Manager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenErc4626Manager.sol";

9: import { IOrigamiLovTokenErc4626Manager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenErc4626Manager.sol";

9: import { IOrigamiLovTokenErc4626Manager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenErc4626Manager.sol";

10: import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

10: import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

10: import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

10: import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

11: import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";

11: import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";

11: import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";

11: import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";

12: import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";

12: import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";

12: import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";

12: import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";

12: import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";

13: import { IOrigamiLendingClerk } from "contracts/interfaces/investments/lending/IOrigamiLendingClerk.sol";

13: import { IOrigamiLendingClerk } from "contracts/interfaces/investments/lending/IOrigamiLendingClerk.sol";

13: import { IOrigamiLendingClerk } from "contracts/interfaces/investments/lending/IOrigamiLendingClerk.sol";

13: import { IOrigamiLendingClerk } from "contracts/interfaces/investments/lending/IOrigamiLendingClerk.sol";

14: import { IOrigamiLendingBorrower } from "contracts/interfaces/investments/lending/IOrigamiLendingBorrower.sol";

14: import { IOrigamiLendingBorrower } from "contracts/interfaces/investments/lending/IOrigamiLendingBorrower.sol";

14: import { IOrigamiLendingBorrower } from "contracts/interfaces/investments/lending/IOrigamiLendingBorrower.sol";

14: import { IOrigamiLendingBorrower } from "contracts/interfaces/investments/lending/IOrigamiLendingBorrower.sol";

16: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

16: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

17: import { OrigamiAbstractLovTokenManager } from "contracts/investments/lovToken/managers/OrigamiAbstractLovTokenManager.sol";

17: import { OrigamiAbstractLovTokenManager } from "contracts/investments/lovToken/managers/OrigamiAbstractLovTokenManager.sol";

17: import { OrigamiAbstractLovTokenManager } from "contracts/investments/lovToken/managers/OrigamiAbstractLovTokenManager.sol";

17: import { OrigamiAbstractLovTokenManager } from "contracts/investments/lovToken/managers/OrigamiAbstractLovTokenManager.sol";

18: import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

18: import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

19: import { DynamicFees } from "contracts/libraries/DynamicFees.sol";

19: import { DynamicFees } from "contracts/libraries/DynamicFees.sol";

184:             if (amount > (bal - _internalReservesBalance)) revert CommonEventsAndErrors.InvalidAmount(token, amount);

347:             _reservesAmount -= reserveAssetSharesWithdrawn;

397:         _reservesAmount += reserveTokensReceived;

442:         _internalReservesBalance += newReservesAmount;

505:         _internalReservesBalance -= reservesAmount;

```

```solidity
File: contracts/investments/lovToken/managers/OrigamiLovTokenFlashAndBorrowManager.sol

5: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

5: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

5: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

5: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

5: import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

6: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

6: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

6: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

6: import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

7: import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

7: import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

7: import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

7: import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

7: import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

9: import { IOrigamiLovTokenFlashAndBorrowManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenFlashAndBorrowManager.sol";

9: import { IOrigamiLovTokenFlashAndBorrowManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenFlashAndBorrowManager.sol";

9: import { IOrigamiLovTokenFlashAndBorrowManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenFlashAndBorrowManager.sol";

9: import { IOrigamiLovTokenFlashAndBorrowManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenFlashAndBorrowManager.sol";

9: import { IOrigamiLovTokenFlashAndBorrowManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenFlashAndBorrowManager.sol";

10: import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

10: import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

10: import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

10: import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

11: import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";

11: import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";

11: import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";

11: import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";

12: import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";

12: import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";

12: import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";

12: import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";

12: import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";

13: import { IOrigamiFlashLoanProvider } from "contracts/interfaces/common/flashLoan/IOrigamiFlashLoanProvider.sol";

13: import { IOrigamiFlashLoanProvider } from "contracts/interfaces/common/flashLoan/IOrigamiFlashLoanProvider.sol";

13: import { IOrigamiFlashLoanProvider } from "contracts/interfaces/common/flashLoan/IOrigamiFlashLoanProvider.sol";

13: import { IOrigamiFlashLoanProvider } from "contracts/interfaces/common/flashLoan/IOrigamiFlashLoanProvider.sol";

15: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

15: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

16: import { OrigamiAbstractLovTokenManager } from "contracts/investments/lovToken/managers/OrigamiAbstractLovTokenManager.sol";

16: import { OrigamiAbstractLovTokenManager } from "contracts/investments/lovToken/managers/OrigamiAbstractLovTokenManager.sol";

16: import { OrigamiAbstractLovTokenManager } from "contracts/investments/lovToken/managers/OrigamiAbstractLovTokenManager.sol";

16: import { OrigamiAbstractLovTokenManager } from "contracts/investments/lovToken/managers/OrigamiAbstractLovTokenManager.sol";

17: import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

17: import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

18: import { Range } from "contracts/libraries/Range.sol";

18: import { Range } from "contracts/libraries/Range.sol";

19: import { DynamicFees } from "contracts/libraries/DynamicFees.sol";

19: import { DynamicFees } from "contracts/libraries/DynamicFees.sol";

20: import { IOrigamiBorrowAndLend } from "contracts/interfaces/common/borrowAndLend/IOrigamiBorrowAndLend.sol";

20: import { IOrigamiBorrowAndLend } from "contracts/interfaces/common/borrowAndLend/IOrigamiBorrowAndLend.sol";

20: import { IOrigamiBorrowAndLend } from "contracts/interfaces/common/borrowAndLend/IOrigamiBorrowAndLend.sol";

20: import { IOrigamiBorrowAndLend } from "contracts/interfaces/common/borrowAndLend/IOrigamiBorrowAndLend.sol";

323:         _debtToken.safeTransfer(msg.sender, amount+fee);

343:         uint256 flashRepayAmount = flashLoanAmount + fee;

351:             (uint256 amountRepaid, /*uint256 withdrawnAmount*/) = _borrowLend.repayAndWithdraw(flashLoanAmount, params.collateralToWithdraw, address(this));

351:             (uint256 amountRepaid, /*uint256 withdrawnAmount*/) = _borrowLend.repayAndWithdraw(flashLoanAmount, params.collateralToWithdraw, address(this));

351:             (uint256 amountRepaid, /*uint256 withdrawnAmount*/) = _borrowLend.repayAndWithdraw(flashLoanAmount, params.collateralToWithdraw, address(this));

351:             (uint256 amountRepaid, /*uint256 withdrawnAmount*/) = _borrowLend.repayAndWithdraw(flashLoanAmount, params.collateralToWithdraw, address(this));

373:             uint256 surplusAfterSwap = _debtToken.balanceOf(address(this)) - flashRepayAmount;

375:             uint256 totalSurplus = borrowLendSurplus + surplusAfterSwap;

380:                 totalDebtRepaid += _borrowLend.repay(totalSurplus);

427:         uint256 borrowAmount = flashLoanAmount + fee;

```

```solidity
File: contracts/investments/util/OrigamiManagerPausable.sol

5: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

5: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

6: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

6: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

6: import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

7: import { IOrigamiManagerPausable } from "contracts/interfaces/investments/util/IOrigamiManagerPausable.sol";

7: import { IOrigamiManagerPausable } from "contracts/interfaces/investments/util/IOrigamiManagerPausable.sol";

7: import { IOrigamiManagerPausable } from "contracts/interfaces/investments/util/IOrigamiManagerPausable.sol";

7: import { IOrigamiManagerPausable } from "contracts/interfaces/investments/util/IOrigamiManagerPausable.sol";

```

```solidity
File: contracts/libraries/Chainlink.sol

5: import { IAggregatorV3Interface } from "contracts/interfaces/external/chainlink/IAggregatorV3Interface.sol";

5: import { IAggregatorV3Interface } from "contracts/interfaces/external/chainlink/IAggregatorV3Interface.sol";

5: import { IAggregatorV3Interface } from "contracts/interfaces/external/chainlink/IAggregatorV3Interface.sol";

5: import { IAggregatorV3Interface } from "contracts/interfaces/external/chainlink/IAggregatorV3Interface.sol";

6: import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

6: import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

6: import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

6: import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

7: import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

7: import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

35:             block.timestamp - lastUpdatedAt > stalenessThreshold

61:                 scalar = uint128(10) ** (targetDecimals - oracleDecimals);

61:                 scalar = uint128(10) ** (targetDecimals - oracleDecimals);

61:                 scalar = uint128(10) ** (targetDecimals - oracleDecimals);

64:                 scalar = uint128(10) ** (oracleDecimals - targetDecimals);

64:                 scalar = uint128(10) ** (oracleDecimals - targetDecimals);

64:                 scalar = uint128(10) ** (oracleDecimals - targetDecimals);

```

```solidity
File: contracts/libraries/CompoundedInterest.sol

5: import { ud } from "@prb/math/src/UD60x18.sol";

5: import { ud } from "@prb/math/src/UD60x18.sol";

5: import { ud } from "@prb/math/src/UD60x18.sol";

22:         uint256 exponent = elapsed * interestRate / ONE_YEAR;

22:         uint256 exponent = elapsed * interestRate / ONE_YEAR;

```

```solidity
File: contracts/libraries/DynamicFees.sol

5: import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

5: import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

5: import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

5: import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

6: import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

6: import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

7: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

7: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

57:                     _delta = _histPrice - _spotPrice;

59:                     _delta = _spotPrice - _histPrice;

69:                     _delta = _spotPrice - _histPrice;

71:                     _delta = _histPrice - _spotPrice;

84:             feeLeverageFactor * OrigamiMath.BASIS_POINTS_DIVISOR,

```

```solidity
File: contracts/libraries/OrigamiMath.sol

5: import { mulDiv as prbMulDiv } from "@prb/math/src/Common.sol";

5: import { mulDiv as prbMulDiv } from "@prb/math/src/Common.sol";

5: import { mulDiv as prbMulDiv } from "@prb/math/src/Common.sol";

6: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

6: import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

23:         return scalar == 1 ? amount : amount * scalar;

36:             result = amount / scalar;

39:             result = amount == 0 ? 0 : (amount - 1) / scalar + 1;

39:             result = amount == 0 ? 0 : (amount - 1) / scalar + 1;

39:             result = amount == 0 ? 0 : (amount - 1) / scalar + 1;

55:             result += 1;

62:             numeratorBps = BASIS_POINTS_DIVISOR - basisPoints;

78:             numeratorBps = BASIS_POINTS_DIVISOR + basisPoints;

98:             removed = inputAmount - result;

108:         if (basisPoints == 0) return remainderAmount; // gas shortcut for 0

108:         if (basisPoints == 0) return remainderAmount; // gas shortcut for 0

113:             denominatorBps = BASIS_POINTS_DIVISOR - basisPoints;

```

### <a name="GAS-3"></a>[GAS-3] Don't initialize variables with default value

*Instances (3)*:
```solidity
File: contracts/common/borrowAndLend/OrigamiAaveV3BorrowAndLend.sol

66:     uint16 public override referralCode = 0;

```

```solidity
File: contracts/common/circuitBreaker/OrigamiCircuitBreakerAllUsersPerPeriod.sol

206:             for (uint256 i = 0; i < _nBuckets; ++i) {

```

```solidity
File: contracts/common/flashLoan/OrigamiAaveV3FlashLoanProvider.sol

38:     uint16 public constant REFERRAL_CODE = 0;

```

### <a name="GAS-4"></a>[GAS-4] Functions guaranteed to revert when called by normal users can be marked `payable`
If a function modifier such as `onlyOwner` is used, the function will revert if a normal user tries to pay the function. Marking the function as `payable` will lower the gas cost for legitimate callers because the compiler will not include checks for whether a payment was provided.

*Instances (81)*:
```solidity
File: contracts/common/MintableToken.sol

47:     function addMinter(address account) external onlyElevatedAccess {

52:     function removeMinter(address account) external onlyElevatedAccess {

63:     function recoverToken(address token, address to, uint256 amount) external virtual onlyElevatedAccess {

```

```solidity
File: contracts/common/RepricingToken.sol

74:     function setReservesVestingDuration(uint256 _reservesVestingDuration) external onlyElevatedAccess {

81:     function recoverToken(address _token, address _to, uint256 _amount) external onlyElevatedAccess {

155:     function addPendingReserves(uint256 amount) external override onlyElevatedAccess {

```

```solidity
File: contracts/common/access/OrigamiElevatedAccessBase.sol

36:     function proposeNewOwner(address account) external override onlyElevatedAccess {

58:     function setExplicitAccess(address allowedCaller, ExplicitAccess[] calldata access) external override onlyElevatedAccess {

```

```solidity
File: contracts/common/access/Whitelisted.sol

27:     function setAllowAll(bool value) external override onlyElevatedAccess {

35:     function setAllowAccount(address account, bool value) external override onlyElevatedAccess {

```

```solidity
File: contracts/common/borrowAndLend/OrigamiAaveV3BorrowAndLend.sol

110:     function setPositionOwner(address account) external override onlyElevatedAccess {

118:     function setReferralCode(uint16 code) external override onlyElevatedAccess {

126:     function setUserUseReserveAsCollateral(bool useAsCollateral) external override onlyElevatedAccess {

133:     function setEModeCategory(uint8 categoryId) external override onlyElevatedAccess {

207:     function reclaimSurplusDebt(uint256 amount, address recipient) external override onlyPositionOwner {

221:     function recoverToken(address token, address to, uint256 amount) external onlyElevatedAccess {       

```

```solidity
File: contracts/common/circuitBreaker/OrigamiCircuitBreakerAllUsersPerPeriod.sol

98:     function preCheck(address /*onBehalfOf*/, uint256 amount) external override onlyProxy {

134:     function setConfig(uint32 _periodDuration, uint32 _nBuckets, uint128 _cap) external onlyElevatedAccess {

141:     function updateCap(uint128 newCap) external onlyElevatedAccess {

```

```solidity
File: contracts/common/swappers/OrigamiDexAggregatorSwapper.sol

44:     function recoverToken(address token, address to, uint256 amount) external onlyElevatedAccess {

```

```solidity
File: contracts/investments/OrigamiInvestmentVault.sol

88:     function setTokenPrices(address _tokenPrices) external onlyElevatedAccess {

98:     function setPerformanceFee(uint256 _performanceFee) external onlyElevatedAccess {

```

```solidity
File: contracts/investments/OrigamiOToken.sol

45:     function setManager(address _manager) external override onlyElevatedAccess {

54:     function amoMint(address _to, uint256 _amount) external override onlyElevatedAccess {

64:     function amoBurn(address _account, uint256 _amount) external override onlyElevatedAccess {

```

```solidity
File: contracts/investments/lending/OrigamiDebtToken.sol

93:     function setMinter(address account, bool value) external override onlyElevatedAccess {

119:     function mint(address _debtor, uint256 _mintAmount) external override onlyMinters {

148:     function burnAll(address _debtor) external override onlyMinters returns (uint256 burnedAmount) {

487:     function recoverToken(address token, address to, uint256 amount) external onlyElevatedAccess {

```

```solidity
File: contracts/investments/lending/OrigamiLendingClerk.sol

141:     function setSupplyManager(address _supplyManager) external override onlyElevatedAccess {

150:     function setGlobalPaused(bool _pauseBorrow, bool _pauseRepay) external override onlyElevatedAccess {

173:     function setGlobalInterestRateModel(address _globalInterestRateModel) external override onlyElevatedAccess {

218:     function setBorrowerDebtCeiling(address borrower, uint256 newDebtCeiling) external override onlyElevatedAccess {

256:     function setIdleStrategyInterestRate(uint96 rate) external override onlyElevatedAccess {

265:     function shutdownBorrower(address borrower) external override onlyElevatedAccess {

276:     function refreshBorrowersInterestRate(address[] calldata borrowerList) external override onlyElevatedAccess {

312:     function recoverToken(address token, address to, uint256 amount) external onlyElevatedAccess {

326:     function deposit(uint256 amount) external override onlySupplyManager {

344:     function withdraw(uint256 amount, address recipient) external override onlySupplyManager {

```

```solidity
File: contracts/investments/lending/OrigamiLendingRewardsMinter.sol

79:     function setCarryOverRate(uint256 _carryOverRate) external override onlyElevatedAccess {

88:     function setFeeCollector(address _feeCollector) external override onlyElevatedAccess {

100:     function recoverToken(address token, address to, uint256 amount) external onlyElevatedAccess {

111:     function checkpointDebtAndMintRewards(address[] calldata debtors) external override onlyElevatedAccess {

```

```solidity
File: contracts/investments/lending/OrigamiLendingSupplyManager.sol

89:     function setLendingClerk(address _lendingClerk) external override onlyElevatedAccess {

109:     function recoverToken(address token, address to, uint256 amount) external onlyElevatedAccess {

```

```solidity
File: contracts/investments/lending/idleStrategy/OrigamiAaveV3IdleStrategy.sol

45:     function allocate(uint256 amount) external override onlyElevatedAccess {

58:     function withdraw(uint256 amount, address recipient) external override onlyElevatedAccess returns (uint256 amountOut) {

74:     function recoverToken(address token, address to, uint256 amount) external override onlyElevatedAccess {

```

```solidity
File: contracts/investments/lending/idleStrategy/OrigamiIdleStrategyManager.sol

77:     function setIdleStrategy(address _idleStrategy) external override onlyElevatedAccess {

95:     function setDepositsEnabled(bool value) external override onlyElevatedAccess {

117:     function allocate(uint256 amount) external override onlyElevatedAccess {

143:     function withdraw(uint256 amount, address recipient) external onlyElevatedAccess {

182:     function allocateFromManager(uint256 amount) external override onlyElevatedAccess {

190:     function withdrawToManager(uint256 amount) external override onlyElevatedAccess returns (uint256) {

200:     function recoverToken(address token, address to, uint256 amount) external onlyElevatedAccess {

```

```solidity
File: contracts/investments/lovToken/OrigamiLovToken.sol

81:     function setManager(address _manager) external override onlyElevatedAccess {

91:     function setPerformanceFee(uint256 _performanceFee) external override onlyElevatedAccess {

100:     function setFeeCollector(address _feeCollector) external override onlyElevatedAccess {

109:     function setTokenPrices(address _tokenPrices) external override onlyElevatedAccess {

191:     function collectPerformanceFees() external override onlyElevatedAccess returns (uint256 amount) {

```

```solidity
File: contracts/investments/lovToken/managers/OrigamiAbstractLovTokenManager.sol

135:     function setRedeemableReservesBufferBps(uint16 buffer) external override onlyElevatedAccess {

148:     function setUserALRange(uint128 floor, uint128 ceiling) external override onlyElevatedAccess {

160:     function setRebalanceALRange(uint128 floor, uint128 ceiling) external override onlyElevatedAccess {

```

```solidity
File: contracts/investments/lovToken/managers/OrigamiLovTokenErc4626Manager.sol

98:     function setLendingClerk(address _lendingClerk) external override onlyElevatedAccess {

115:     function setSwapper(address _swapper) external override onlyElevatedAccess {

136:     function setOracle(address oracle) external override onlyElevatedAccess {

145:     function rebalanceUp(RebalanceUpParams calldata params) external override onlyElevatedAccess returns (uint128 alRatioAfter) {

153:     function forceRebalanceUp(RebalanceUpParams calldata params) external override onlyElevatedAccess returns (uint128 alRatioAfter) {

160:     function rebalanceDown(RebalanceDownParams calldata params) external override onlyElevatedAccess returns (uint128 alRatioAfter) {

168:     function forceRebalanceDown(RebalanceDownParams calldata params) external override onlyElevatedAccess returns (uint128 alRatioAfter) {

179:     function recoverToken(address token, address to, uint256 amount) external override onlyElevatedAccess {

```

```solidity
File: contracts/investments/lovToken/managers/OrigamiLovTokenFlashAndBorrowManager.sol

97:     function setSwapper(address _swapper) external override onlyElevatedAccess {

116:     function setOracle(address oracle) external override onlyElevatedAccess {

125:     function setFlashLoanProvider(address provider) external override onlyElevatedAccess {

134:     function setBorrowLend(address _address) external override onlyElevatedAccess {

143:     function rebalanceUp(RebalanceUpParams calldata params) external override onlyElevatedAccess {

159:     function forceRebalanceUp(RebalanceUpParams calldata params) external override onlyElevatedAccess {

175:     function rebalanceDown(RebalanceDownParams calldata params) external override onlyElevatedAccess {

191:     function forceRebalanceDown(RebalanceDownParams calldata params) external override onlyElevatedAccess {

210:     function recoverToken(address token, address to, uint256 amount) external override onlyElevatedAccess {

```

```solidity
File: contracts/investments/util/OrigamiManagerPausable.sol

37:     function setPauser(address account, bool canPause) external onlyElevatedAccess {

```

### <a name="GAS-5"></a>[GAS-5] Using `private` rather than `public` for constants, saves gas
If needed, the values can be read from the verified contract source code, or if there are multiple values there can be a single getter function that [returns a tuple](https://github.com/code-423n4/2022-08-frax/blob/90f55a9ce4e25bceed3a74290b854341d8de6afa/src/contracts/FraxlendPair.sol#L156-L178) of the values of all currently-public constants. Saves **3406-3606 gas** in deployment gas due to the compiler not having to create non-payable getter functions for deployment calldata, not having to store the bytes of the value outside of where it's used, and not adding another entry to the method ID table

*Instances (13)*:
```solidity
File: contracts/common/circuitBreaker/OrigamiCircuitBreakerAllUsersPerPeriod.sol

73:     uint32 public constant MAX_BUCKETS = 4000;

```

```solidity
File: contracts/common/flashLoan/OrigamiAaveV3FlashLoanProvider.sol

38:     uint16 public constant REFERRAL_CODE = 0;

```

```solidity
File: contracts/common/oracle/OrigamiOracleBase.sol

29:     uint8 public constant override decimals = 18;

34:     uint256 public constant override precision = 1e18;

```

```solidity
File: contracts/investments/OrigamiInvestment.sol

15:     string public constant API_VERSION = "0.2.0";

```

```solidity
File: contracts/investments/OrigamiInvestmentVault.sol

34:     string public constant API_VERSION = "0.2.0";

```

```solidity
File: contracts/investments/lending/OrigamiDebtToken.sol

63:     uint8 public constant override decimals = 18;

```

```solidity
File: contracts/investments/lending/idleStrategy/OrigamiIdleStrategyManager.sol

60:     string public constant override version = "1.0.0";

65:     string public constant override name = "IdleStrategyManager";

```

```solidity
File: contracts/investments/lovToken/managers/OrigamiAbstractLovTokenManager.sol

75:     uint256 public constant override PRECISION = 1e18;

```

```solidity
File: contracts/investments/lovToken/managers/OrigamiLovTokenErc4626Manager.sol

80:     string public constant override version = "1.0.0";

```

```solidity
File: contracts/libraries/CompoundedInterest.sol

11:     uint256 public constant ONE_YEAR = 365 days;

```

```solidity
File: contracts/libraries/OrigamiMath.sol

18:     uint256 public constant BASIS_POINTS_DIVISOR = 10_000;

```


## Non Critical Issues


| |Issue|Instances|
|-|:-|:-:|
| [NC-1](#NC-1) | Constants should be defined rather than using magic numbers | 2 |
### <a name="NC-1"></a>[NC-1] Constants should be defined rather than using magic numbers

*Instances (2)*:
```solidity
File: contracts/investments/lovToken/managers/OrigamiAbstractLovTokenManager.sol

528:             if (ee < MAX_EFECTIVE_EXPOSURE) {

529:                 return uint128(ee);

```


## Low Issues


| |Issue|Instances|
|-|:-|:-:|
| [L-1](#L-1) | Empty Function Body - Consider commenting why | 4 |
| [L-2](#L-2) | Initializers could be front-run | 2 |
### <a name="L-1"></a>[L-1] Empty Function Body - Consider commenting why

*Instances (4)*:
```solidity
File: contracts/common/MintableToken.sol

35:     {}

```

```solidity
File: contracts/common/circuitBreaker/OrigamiCircuitBreakerProxy.sol

42:     {}

```

```solidity
File: contracts/investments/OrigamiOToken.sol

40:     ) OrigamiInvestment(_name, _symbol, _initialOwner) {}

```

```solidity
File: contracts/investments/lovToken/managers/OrigamiAbstractLovTokenManager.sol

601:     function _validateAlRange(Range.Data storage range) internal virtual view {}

```

### <a name="L-2"></a>[L-2] Initializers could be front-run
Initializers could be front-run, allowing an attacker to either set their own values, take ownership of the contract, and in the best case forcing a re-deployment

*Instances (2)*:
```solidity
File: contracts/common/access/OrigamiElevatedAccess.sol

12:         _init(initialOwner);

```

```solidity
File: contracts/common/access/OrigamiElevatedAccessBase.sol

26:     function _init(address initialOwner) internal {

```

