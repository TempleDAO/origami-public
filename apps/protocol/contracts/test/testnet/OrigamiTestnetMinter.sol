pragma solidity 0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CommonEventsAndErrors} from "contracts/common/CommonEventsAndErrors.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IMintable {
    function mint(address _account, uint256 _amount) external;
}

/// @title Origami Testnet Minter
/// @notice Mint test tokens for a given address
contract OrigamiTestnetMinter {
    using SafeERC20 for IERC20;

    enum MintType {
        MINT,
        TRANSFER
    }

    struct MintPair {
        address token;
        uint256 amount;
        MintType mintType;
    }

    MintPair[] public mintPairs;

    mapping(address => uint256) public lastMinted;
    uint256 public minMintThresholdSecs;

    event MintedPairs(address indexed user);
    error TooManyPairs();
    error TooSoon();

    constructor(MintPair[] memory _mintPairs, uint256 _minMintThresholdSecs) {
        setMintPairs(_mintPairs, _minMintThresholdSecs);
    }

    function setMintPairs(MintPair[] memory _mintPairs, uint256 _minMintThresholdSecs) public {
        uint256 numPairs = _mintPairs.length;
        if (numPairs > 10) revert TooManyPairs();

        // Can't copy memory => storage, so have to push one by one.
        delete mintPairs;
        for (uint256 i; i < numPairs; ++i) {
            mintPairs.push(_mintPairs[i]);
        }

        minMintThresholdSecs = _minMintThresholdSecs;
    }

    function mint() external {
        emit MintedPairs(msg.sender);

        if (block.timestamp - lastMinted[msg.sender] < minMintThresholdSecs) revert TooSoon();
        lastMinted[msg.sender] = block.timestamp;

        uint256 numPairs = mintPairs.length;
        MintPair storage pair;
        for (uint256 i; i < numPairs; ++i) {
            pair = mintPairs[i];
            if (pair.mintType == MintType.MINT) {
                IMintable(pair.token).mint(msg.sender, pair.amount);
            } else if (pair.mintType == MintType.TRANSFER) {
                if (IERC20(pair.token).balanceOf(address(this)) > pair.amount) {
                    IERC20(pair.token).safeTransfer(msg.sender, pair.amount);
                }
            }
        }
    }

    function recoverToken(address _token, address _to, uint256 _amount) external {
        emit CommonEventsAndErrors.TokenRecovered(_to, _token, _amount);
        IERC20(_token).safeTransfer(_to, _amount);
    }

}
