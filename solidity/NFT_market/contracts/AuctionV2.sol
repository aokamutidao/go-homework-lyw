// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./AuctionV1.sol";

/**
 * @title AuctionV2
 * @dev 拍卖合约 V2 版本，新增动态手续费功能
 */
contract AuctionV2 is AuctionV1 {
    // 动态手续费配置
    struct DynamicFeeConfig {
        uint256 minFeePercent;      // 最小手续费
        uint256 maxFeePercent;      // 最大手续费
        uint256 feeThreshold;       // 阈值金额
        uint256 feeMultiplier;      // 动态乘数
    }

    DynamicFeeConfig public dynamicFeeConfig;

    // 版本号
    string public constant version = "2.0.0";

    // 新事件
    event DynamicFeeConfigUpdated(
        uint256 minFeePercent,
        uint256 maxFeePercent,
        uint256 feeThreshold,
        uint256 feeMultiplier
    );

    /**
     * @dev V2 初始化函数
     */
    function initializeV2(
        uint256 _minFeePercent,
        uint256 _maxFeePercent,
        uint256 _feeThreshold,
        uint256 _feeMultiplier
    ) public reinitializer(2) {
        dynamicFeeConfig = DynamicFeeConfig({
            minFeePercent: _minFeePercent,
            maxFeePercent: _maxFeePercent,
            feeThreshold: _feeThreshold,
            feeMultiplier: _feeMultiplier
        });

        emit DynamicFeeConfigUpdated(
            _minFeePercent,
            _maxFeePercent,
            _feeThreshold,
            _feeMultiplier
        );
    }

    /**
     * @dev 计算动态手续费
     */
    function calculateFee(uint256 bidAmount) public view returns (uint256) {
        FeeConfig memory baseConfig = feeConfig;
        DynamicFeeConfig memory dynamic = dynamicFeeConfig;

        if (dynamic.maxFeePercent == 0) {
            // 使用基础手续费
            return (bidAmount * baseConfig.feePercent) / 1e18;
        }

        // 基础手续费
        uint256 baseFee = (bidAmount * baseConfig.feePercent) / 1e18;

        // 动态调整
        uint256 adjustedFee;
        if (bidAmount > dynamic.feeThreshold) {
            // 高价值拍卖，手续费降低
            uint256 reduction = ((bidAmount - dynamic.feeThreshold) * dynamic.feeMultiplier) / 1e18;
            if (reduction > dynamic.maxFeePercent - baseConfig.feePercent) {
                reduction = dynamic.maxFeePercent - baseConfig.feePercent;
            }
            adjustedFee = baseFee * (1e18 - reduction) / 1e18;
        } else {
            // 低价值拍卖，手续费可能略高但不超过最大值
            uint256 increase = ((dynamic.feeThreshold - bidAmount) * dynamic.feeMultiplier) / 1e18;
            if (increase > dynamic.minFeePercent - baseConfig.feePercent) {
                increase = dynamic.minFeePercent - baseConfig.feePercent;
            }
            adjustedFee = baseFee * (1e18 + increase) / 1e18;
        }

        // 确保在范围内
        uint256 minFee = (bidAmount * dynamic.minFeePercent) / 1e18;
        uint256 maxFee = (bidAmount * dynamic.maxFeePercent) / 1e18;

        if (adjustedFee < minFee) return minFee;
        if (adjustedFee > maxFee) return maxFee;

        return adjustedFee;
    }

    /**
     * @dev 设置动态手续费配置
     */
    function setDynamicFeeConfig(
        uint256 _minFeePercent,
        uint256 _maxFeePercent,
        uint256 _feeThreshold,
        uint256 _feeMultiplier
    ) external onlyOwner {
        require(_minFeePercent <= _maxFeePercent, "Invalid fee config");
        require(_maxFeePercent <= 0.1e18, "Max fee too high");

        dynamicFeeConfig = DynamicFeeConfig({
            minFeePercent: _minFeePercent,
            maxFeePercent: _maxFeePercent,
            feeThreshold: _feeThreshold,
            feeMultiplier: _feeMultiplier
        });

        emit DynamicFeeConfigUpdated(
            _minFeePercent,
            _maxFeePercent,
            _feeThreshold,
            _feeMultiplier
        );
    }

    /**
     * @dev 获取预计手续费
     */
    function getEstimatedFee(uint256 auctionId) external view returns (uint256) {
        Auction storage auction = auctions[auctionId];
        return calculateFee(auction.highestBid);
    }
}
