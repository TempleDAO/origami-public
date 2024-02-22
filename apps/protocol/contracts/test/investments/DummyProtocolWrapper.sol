pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";

contract DummyProtocolWrapper {
    function investWithToken(
        IOrigamiInvestment investment,
        IOrigamiInvestment.InvestQuoteData calldata quoteData
    ) external returns (uint256) {
        return investment.investWithToken(quoteData);
    }

    function investWithNative(
        IOrigamiInvestment investment,
        IOrigamiInvestment.InvestQuoteData calldata quoteData
    ) external payable returns (uint256) {
        return investment.investWithNative{value: msg.value}(quoteData);
    }
}
