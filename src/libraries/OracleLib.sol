// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {AggregatorV3Interface} from "lib/chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
@notice thư viện này sử dụng để kiểm tra chainlink Oracle stale data.
Nếu price stale (giá không thay đổi), thì mọi functions sẽ revert, DSC Engine sẽ không sử dụng được
SCEngine to freeze if prices become stale.
Vì vậy, nếu mạng Chainlink bùng nổ và bạn có rất nhiều tiền bị khóa trong giao thức... thì thật tệ.
 */
library OracleLib {
    error OracleLib__StalePrice();

    uint256 private constant TIMEOUT = 3 hours; // 10800s

    function staleCheckLastedRoundData(
        AggregatorV3Interface priceFeed
    ) public view returns (uint80, int256, uint256, uint256, uint80) {
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();

        uint256 secondsSince = block.timestamp - updatedAt;

        if (secondsSince > TIMEOUT) revert OracleLib__StalePrice();
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
