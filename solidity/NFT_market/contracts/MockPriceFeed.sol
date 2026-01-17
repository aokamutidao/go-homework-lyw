// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MockPriceFeed
 * @dev 用于本地测试的 Mock Chainlink Price Feed
 */
contract MockPriceFeed {
    int256 private _price;
    uint8 private _decimals;
    uint256 private _timestamp;
    uint256 private _roundId;

    constructor(int256 initialPrice, uint8 decimals_) {
        _price = initialPrice;
        _decimals = decimals_;
        _timestamp = block.timestamp;
        _roundId = 1;
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (
            uint80(_roundId),
            _price,
            _timestamp,
            _timestamp,
            uint80(_roundId)
        );
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function setPrice(int256 newPrice) external {
        _price = newPrice;
        _timestamp = block.timestamp;
        _roundId++;
    }

    function getPrice() external view returns (int256) {
        return _price;
    }
}
