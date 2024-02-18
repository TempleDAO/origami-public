// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./interfaces/GMX_IVault.sol";
import "../access/GMX_Governable.sol";

contract GMX_VaultErrorController is GMX_Governable {
    function setErrors(GMX_IVault _vault, string[] calldata _errors) external onlyGov {
        for (uint256 i = 0; i < _errors.length; i++) {
            _vault.setError(i, _errors[i]);
        }
    }
}
