// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title PriceOracle
 * @dev 使用 Chainlink Price Feed 获取代币价格
 */
contract PriceOracle {
    // Chainlink Price Feed 地址映射
    mapping(address => address) public priceFeeds;

    // 代币地址 -> 名称（如 "ETH/USD", "LINK/USD"）
    mapping(address => string) public feedNames;

    // 支持的代币地址列表（用于遍历查询）
    address[] public supportedTokens;

    // 避免重复添加
    mapping(address => bool) public tokenExists;

    // 事件
    event PriceFeedUpdated(address token, address feed, string name);
    event PriceRequested(
        address token,
        uint256 price,
        uint256 timestamp
    );

    // 精度常量
    uint8 public constant DECIMALS = 8; // chainlink官方规范
    uint256 public constant PRECISION = 1e18; //  solidity标准精度

    /**
     * @dev 内部函数：添加价格Feed
     */
    function _addPriceFeed(address token, address feed, string memory name) internal {
        require(feed != address(0), "Invalid feed address");

        // 如果是新代币，加入列表
        if (!tokenExists[token]) {
            tokenExists[token] = true;
            supportedTokens.push(token);
        }

        priceFeeds[token] = feed;
        feedNames[token] = name;
    }

    constructor() {
        // Sepolia 测试网价格Feed地址
        // ETH/USD
        _addPriceFeed(address(0), 0x694AA1769357215DE4FAC081bf1f309aDC325306, "ETH/USD");

        // LINK/USD
        _addPriceFeed(0x779877A7B0D9E8603169DdbD7836e478b4624789, 0xc59E3633BAAC7949054ecF67bfbE17F056c9D407, "LINK/USD");
    }

    /**
     * @dev 设置价格Feed地址和名称
     * @param token 代币地址
     * @param feed Chainlink Price Feed 地址
     * @param name 名称（如 "BTC/USD"）
     */
    function setPriceFeed(address token, address feed, string memory name) external {
        _addPriceFeed(token, feed, name);
        emit PriceFeedUpdated(token, feed, name);
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
            feeds[i] = priceFeeds[token];
        }
    }

    /**
     * @dev 获取代币的美元价格
     * @param token 代币地址（address(0) 表示 ETH）
     * @return price 代币的美元价格（精度 1e18）
     */
    function getPrice(address token) external view returns (uint256 price) {
        address feedAddr = priceFeeds[token];
        require(feedAddr != address(0), "Price feed not set");

        (, int256 answer, , , ) = AggregatorV3Interface(feedAddr)
            .latestRoundData();

        require(answer > 0, "Invalid price");

        // Chainlink 返回的价格精度是 8 位小数
        // 转换为 18 位精度
        return uint256(answer) * 1e10;
    }

    /**
     * @dev 获取 ETH 的美元价格
     */
    function getEthPrice() external view returns (uint256) {
        return getPrice(address(0));
    }

    /**
     * @dev 将代币数量转换为美元
     * @param token 代币地址
     * @param amount 代币数量
     * @return usdValue 等价的美元价值
     */
    function getValueInUSD(address token, uint256 amount)
        external
        view
        returns (uint256 usdValue)
    {
        uint256 price = getPrice(token);
        // price 是 1e18 精度（每个代币的美元价格）
        // amount 是 token 的最小单位数量
        return (price * amount) / PRECISION;
    }

    /**
     * @dev 将 ETH 数量转换为美元
     */
    function getEthValueInUSD(uint256 ethAmount)
        external
        view
        returns (uint256)
    {
        return getValueInUSD(address(0), ethAmount);
    }

    /**
     * @dev 将美元转换为代币数量
     * @param token 代币地址
     * @param usdAmount 美元金额
     * @return tokenAmount 等价的代币数量
     */
    function getAmountFromUSD(address token, uint256 usdAmount)
        external
        view
        returns (uint256 tokenAmount)
    {
        uint256 price = getPrice(token);
        // usdAmount / price 得到代币数量（考虑精度）
        return (usdAmount * PRECISION) / price;
    }

    /**
     * @dev 获取多个代币的价格
     */
    function getMultiplePrices(address[] calldata tokens)
        external
        view
        returns (uint256[] memory prices)
    {
        prices = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            prices[i] = getPrice(tokens[i]);
        }
    }

    /**
     * @dev 检查价格Feed是否可用
     */
    function isFeedAvailable(address token) external view returns (bool) {
        return priceFeeds[token] != address(0);
    }
}
