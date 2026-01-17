// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./MockPriceFeed.sol";

/**
 * @title MockPriceOracle
 * @dev 用于本地测试的 Mock Price Oracle，支持多个代币价格
 */
contract MockPriceOracle {
    // 价格 Feed 映射
    mapping(address => MockPriceFeed) public priceFeeds;

    // 代币地址 -> 名称（如 "ETH/USD", "LINK/USD"）
    mapping(address => string) public feedNames;

    // 支持的代币地址列表
    address[] public supportedTokens;

    // 避免重复添加
    mapping(address => bool) public tokenExists;

    uint256 public constant PRECISION = 1e18;

    // 事件
    event PriceFeedAdded(address token, string name, address feed);
    event PriceUpdated(address token, int256 price);

    // 默认价格
    int256 public defaultEthPrice = 2000e8; // $2000
    int256 public defaultLinkPrice = 10e8;  // $10

    /**
     * @dev 内部函数：添加价格Feed
     */
    function _addPriceFeed(address token, string memory name, MockPriceFeed feed) internal {
        // 如果是新代币，加入列表
        if (!tokenExists[token]) {
            tokenExists[token] = true;
            supportedTokens.push(token);
        }

        priceFeeds[token] = feed;
        feedNames[token] = name;
        emit PriceFeedAdded(token, name, address(feed));
    }

    constructor() {
        // 创建 ETH 价格 Feed
        MockPriceFeed ethFeed = new MockPriceFeed(defaultEthPrice, 8);
        _addPriceFeed(address(0), "ETH/USD", ethFeed);

        // 创建 LINK 价格 Feed
        MockPriceFeed linkFeed = new MockPriceFeed(defaultLinkPrice, 8);
        _addPriceFeed(0x779877A7B0D9E8603169DdbD7836e478b4624789, "LINK/USD", linkFeed);
    }

    /**
     * @dev 设置新的价格Feed
     * @param token 代币地址
     * @param name 名称（如 "BTC/USD"）
     * @param price 初始价格
     */
    function setPriceFeed(address token, string memory name, int256 price) external {
        require(!tokenExists[token], "Token already exists");

        MockPriceFeed newFeed = new MockPriceFeed(price, 8);
        _addPriceFeed(token, name, newFeed);
    }

    /**
     * @dev 更新已有Feed的价格
     */
    function updatePrice(address token, int256 price) external {
        require(tokenExists[token], "Token not found");
        priceFeeds[token].setPrice(price);
        emit PriceUpdated(token, price);
    }

    /**
     * @dev 获取代币名称
     */
    function getFeedName(address token) external view returns (string memory) {
        return feedNames[token];
    }

    /**
     * @dev 获取支持的代币数量
     */
    function getSupportedTokenCount() external view returns (uint256) {
        return supportedTokens.length;
    }

    /**
     * @dev 获取所有支持的代币信息
     */
    function getAllSupportedFeeds() external view returns (
        address[] memory tokens,
        string[] memory names,
        address[] memory feeds
    ) {
        uint256 count = supportedTokens.length;
        tokens = new address[](count);
        names = new string[](count);
        feeds = new address[](count);

        for (uint256 i = 0; i < count; i++) {
            address token = supportedTokens[i];
            tokens[i] = token;
            names[i] = feedNames[token];
            feeds[i] = address(priceFeeds[token]);
        }
    }

    function getValueInUSD(address token, uint256 amount)
        external
        view
        returns (uint256)
    {
        return (getPrice(token) * amount) / PRECISION;
    }

    function getAmountFromUSD(address token, uint256 usdAmount)
        external
        view
        returns (uint256)
    {
        return (usdAmount * PRECISION) / getPrice(token);
    }

    function getPrice(address token) public view returns (uint256) {
        require(address(priceFeeds[token]) != address(0), "Price feed not set");

        (, int256 answer, , , ) = priceFeeds[token].latestRoundData();
        require(answer > 0, "Invalid price");

        // 转换为 18 位精度
        return uint256(answer) * 1e10;
    }

    function isFeedAvailable(address token) external view returns (bool) {
        return tokenExists[token];
    }

    function setDefaultEthPrice(int256 price) external {
        defaultEthPrice = price;
        if (tokenExists[address(0)]) {
            priceFeeds[address(0)].setPrice(price);
        }
    }

    function setDefaultLinkPrice(int256 price) external {
        defaultLinkPrice = price;
        address linkToken = 0x779877A7B0D9E8603169DdbD7836e478b4624789;
        if (tokenExists[linkToken]) {
            priceFeeds[linkToken].setPrice(price);
        }
    }
}
