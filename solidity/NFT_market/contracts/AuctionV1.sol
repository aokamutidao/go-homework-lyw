// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title AuctionV1
 * @dev NFT 拍卖市场合约，支持 ETH 和 ERC20 出价
 */
contract AuctionV1 is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    // 拍卖状态
    enum AuctionStatus {
        Pending,
        Active,
        Ended,
        Cancelled
    }

    // 拍卖信息
    struct Auction {
        uint256 auctionId;
        address seller;
        address nftContract;
        uint256 tokenId;
        uint256 startingPrice;      // 起始价（最小出价）
        uint256 startTime;
        uint256 endTime;
        address highestBidder;
        uint256 highestBid;
        address bidToken;           // 出价代币地址（address(0) 表示 ETH）
        AuctionStatus status;
        bool settled;               // 是否已结算
    }

    // 出价记录
    struct Bid {
        address bidder;
        uint256 amount;
        uint256 timestamp;
    }

    // 手续费配置
    struct FeeConfig {
        uint256 feePercent;         // 手续费百分比（1e18 精度）
        address feeRecipient;       // 手续费接收地址
    }

    // 拍卖相关映射
    mapping(uint256 => Auction) public auctions;
    mapping(uint256 => Bid[]) public bidHistory;
    mapping(address => bool) public supportedTokens;  // 支持的 ERC20 代币

    // 手续费配置
    FeeConfig public feeConfig;

    // 拍卖数量计数器
    uint256 public auctionCount;

    // 最小拍卖时长（秒）
    uint256 public constant MIN_AUCTION_DURATION = 1 hours;
    uint256 public constant MAX_AUCTION_DURATION = 7 days;

    // 价格预言机
    address public priceOracle;

    // 事件
    event AuctionCreated(
        uint256 indexed auctionId,
        address indexed seller,
        address indexed nftContract,
        uint256 tokenId,
        uint256 startingPrice,
        uint256 startTime,
        uint256 endTime
    );

    event BidPlaced(
        uint256 indexed auctionId,
        address indexed bidder,
        uint256 amount,
        address bidToken
    );

    event BidRefunded(
        uint256 indexed auctionId,
        address indexed bidder,
        uint256 amount
    );

    event AuctionEnded(
        uint256 indexed auctionId,
        address indexed winner,
        uint256 finalPrice
    );

    event AuctionCancelled(
        uint256 indexed auctionId,
        address indexed seller
    );

    event FeeConfigUpdated(
        uint256 feePercent,
        address feeRecipient
    );

    event PriceOracleUpdated(
        address indexed oldOracle,
        address indexed newOracle
    );

    // 修饰符
    modifier onlyActiveAuction(uint256 auctionId) {
        require(
            auctions[auctionId].status == AuctionStatus.Active,
            "Auction not active"
        );
        _;
    }

    modifier onlySeller(uint256 auctionId) {
        require(
            auctions[auctionId].seller == msg.sender,
            "Not auction seller"
        );
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 初始化函数
     */
    function initialize(
        address _priceOracle,
        address _feeRecipient,
        uint256 _feePercent
    ) public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        priceOracle = _priceOracle;
        feeConfig = FeeConfig({
            feePercent: _feePercent,
            feeRecipient: _feeRecipient
        });
    }

    /**
     * @dev UUPS 代理升级授权检查
     */
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}

    /**
     * @dev 创建拍卖
     */
    function createAuction(
        address _nftContract,
        uint256 _tokenId,
        uint256 _startingPrice,
        uint256 _duration,
        address _bidToken  // address(0) 表示 ETH
    ) external nonReentrant returns (uint256) {
        require(_startingPrice > 0, "Invalid starting price");
        require(
            _duration >= MIN_AUCTION_DURATION &&
            _duration <= MAX_AUCTION_DURATION,
            "Invalid duration"
        );
        require(
            _bidToken == address(0) || supportedTokens[_bidToken],
            "Unsupported token"
        );

        // 检查 NFT 所有权， 只有nft的所有者能发起拍卖
        require(
            IERC721(_nftContract).ownerOf(_tokenId) == msg.sender,
            "Not NFT owner"
        );
        require(
            IERC721(_nftContract).isApprovedForAll(msg.sender, address(this)) ||
            IERC721(_nftContract).getApproved(_tokenId) == address(this),
            "NFT not approved"
        );

        auctionCount++;
        uint256 auctionId = auctionCount;
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + _duration;

        auctions[auctionId] = Auction({
            auctionId: auctionId,
            seller: msg.sender,
            nftContract: _nftContract,
            tokenId: _tokenId,
            startingPrice: _startingPrice,
            startTime: startTime,
            endTime: endTime,
            highestBidder: address(0),
            highestBid: 0,
            bidToken: _bidToken,
            status: AuctionStatus.Active,
            settled: false
        });

        // 将 NFT 转入合约
        IERC721(_nftContract).transferFrom(msg.sender, address(this), _tokenId);

        emit AuctionCreated(
            auctionId,
            msg.sender,
            _nftContract,
            _tokenId,
            _startingPrice,
            startTime,
            endTime
        );

        return auctionId;
    }

    /**
     * @dev 用 ETH 出价
     */
    function bidWithEth(uint256 auctionId)
        external
        payable
        nonReentrant
        onlyActiveAuction(auctionId)
    {
        require(auctions[auctionId].bidToken == address(0), "Use bidWithToken");
        require(msg.value >= auctions[auctionId].startingPrice, "Bid too low");

        Auction storage auction = auctions[auctionId];

        // 检查拍卖是否结束
        require(block.timestamp < auction.endTime, "Auction ended");

        // 退款给之前的最高出价者
        if (auction.highestBidder != address(0)) {
            _refundBid(auction.highestBidder, auction.highestBid, address(0));
        }

        // 更新最高出价
        auction.highestBidder = msg.sender;
        auction.highestBid = msg.value;

        // 记录出价历史
        bidHistory[auctionId].push(Bid({
            bidder: msg.sender,
            amount: msg.value,
            timestamp: block.timestamp
        }));

        emit BidPlaced(auctionId, msg.sender, msg.value, address(0));
    }

    /**
     * @dev 用 ERC20 代币出价
     */
    function bidWithToken(
        uint256 auctionId,
        uint256 amount
    ) external nonReentrant onlyActiveAuction(auctionId) {
        require(auctions[auctionId].bidToken != address(0), "Use bidWithEth");
        require(amount >= auctions[auctionId].startingPrice, "Bid too low");

        Auction storage auction = auctions[auctionId];
        require(block.timestamp < auction.endTime, "Auction ended");

        // 检查代币授权
        require(
            IERC20(auction.bidToken).allowance(msg.sender, address(this)) >= amount,
            "Insufficient allowance"
        );

        // 退款给之前的最高出价者
        if (auction.highestBidder != address(0)) {
            _refundBid(auction.highestBidder, auction.highestBid, auction.bidToken);
        }

        // 转当代币到合约
        require(
            IERC20(auction.bidToken).transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );

        // 更新最高出价
        auction.highestBidder = msg.sender;
        auction.highestBid = amount;

        // 记录出价历史
        bidHistory[auctionId].push(Bid({
            bidder: msg.sender,
            amount: amount,
            timestamp: block.timestamp
        }));

        emit BidPlaced(auctionId, msg.sender, amount, auction.bidToken);
    }

    /**
     * @dev 结束拍卖（卖家调用）
     */
    function settleAuction(uint256 auctionId)
        external
        nonReentrant
        onlySeller(auctionId)
    {
        Auction storage auction = auctions[auctionId];
        require(auction.status == AuctionStatus.Active, "Auction not active");
        require(block.timestamp >= auction.endTime, "Auction not ended");
        require(!auction.settled, "Already settled");

        auction.settled = true;

        if (auction.highestBidder == address(0)) {
            // 没有出价，取消拍卖，退回 NFT
            auction.status = AuctionStatus.Cancelled;
            IERC721(auction.nftContract).transferFrom(
                address(this),
                auction.seller,
                auction.tokenId
            );
            emit AuctionCancelled(auctionId, auction.seller);
        } else {
            // 有出价，转移 NFT 和资金
            auction.status = AuctionStatus.Ended;

            // 计算手续费
            uint256 fee = (auction.highestBid * feeConfig.feePercent) / 1e18;
            uint256 sellerProceeds = auction.highestBid - fee;

            // 转移手续费
            if (fee > 0) {
                _transferPayment(payable(feeConfig.feeRecipient), auction.highestBid, auction.bidToken);
            }

            // 转移 NFT 给买家
            IERC721(auction.nftContract).transferFrom(
                address(this),
                auction.highestBidder,
                auction.tokenId
            );

            // 转移余额给卖家
            _transferPayment(payable(auction.seller), sellerProceeds, auction.bidToken);

            emit AuctionEnded(auctionId, auction.highestBidder, auction.highestBid);
        }
    }

    /**
     * @dev 卖家提前结束拍卖（必须有至少一个出价）
     */
    function endAuctionEarly(uint256 auctionId) external onlySeller(auctionId) {
        Auction storage auction = auctions[auctionId];
        require(auction.status == AuctionStatus.Active, "Auction not active");
        require(auction.highestBidder != address(0), "No bids yet");

        // 拍卖结束时间改为现在
        auction.endTime = block.timestamp;
    }

    /**
     * @dev 取消拍卖（无出价时）
     */
    function cancelAuction(uint256 auctionId) external onlySeller(auctionId) {
        Auction storage auction = auctions[auctionId];
        require(auction.status == AuctionStatus.Active, "Auction not active");
        require(auction.highestBidder == address(0), "Has bids, cannot cancel");

        auction.status = AuctionStatus.Cancelled;
        IERC721(auction.nftContract).transferFrom(
            address(this),
            auction.seller,
            auction.tokenId
        );

        emit AuctionCancelled(auctionId, auction.seller);
    }

    /**
     * @dev 获取拍卖详情（包含美元价值）
     */
    function getAuctionDetails(uint256 auctionId)
        external
        view
        returns (
            uint256 auctionIdOut,
            address seller,
            address nftContract,
            uint256 tokenId,
            uint256 startingPrice,
            uint256 currentPrice,
            uint256 startTime,
            uint256 endTime,
            address highestBidder,
            uint256 highestBidInUSD,
            AuctionStatus status,
            bool settled
        )
    {
        Auction storage auction = auctions[auctionId];
        auctionIdOut = auction.auctionId;
        seller = auction.seller;
        nftContract = auction.nftContract;
        tokenId = auction.tokenId;
        startingPrice = auction.startingPrice;
        startTime = auction.startTime;
        endTime = auction.endTime;
        highestBidder = auction.highestBidder;
        status = auction.status;
        settled = auction.settled;

        // 计算当前最高出价的美元价值
        if (auction.highestBid > 0) {
            highestBidInUSD = _getUsdValue(auction.bidToken, auction.highestBid);
        }

        // 如果出价高于起始价，使用最高出价
        if (auction.highestBid > 0) {
            currentPrice = auction.highestBid;
        } else {
            currentPrice = auction.startingPrice;
        }
    }

    /**
     * @dev 获取出价历史
     */
    function getBidHistory(uint256 auctionId)
        external
        view
        returns (Bid[] memory)
    {
        return bidHistory[auctionId];
    }

    /**
     * @dev 设置手续费配置
     */
    function setFeeConfig(uint256 feePercent, address feeRecipient)
        external
        onlyOwner
    {
        require(feePercent <= 0.1e18, "Fee too high"); // 最大 10%
        feeConfig.feePercent = feePercent;
        feeConfig.feeRecipient = feeRecipient;
        emit FeeConfigUpdated(feePercent, feeRecipient);
    }

    /**
     * @dev 设置支持的 ERC20 代币
     */
    function setSupportedToken(address token, bool supported)
        external
        onlyOwner
    {
        supportedTokens[token] = supported;
    }

    /**
     * @dev 设置价格预言机
     */
    function setPriceOracle(address newOracle) external onlyOwner {
        address oldOracle = priceOracle;
        priceOracle = newOracle;
        emit PriceOracleUpdated(oldOracle, newOracle);
    }

    /**
     * @dev 批量设置支持的代币
     */
    function setSupportedTokens(address[] calldata tokens, bool supported)
        external
        onlyOwner
    {
        for (uint256 i = 0; i < tokens.length; i++) {
            supportedTokens[tokens[i]] = supported;
        }
    }

    // 内部函数

    function _refundBid(address bidder, uint256 amount, address token) internal {
        _transferPayment(payable(bidder), amount, token);
        emit BidRefunded(0, bidder, amount);
    }

    function _transferPayment(address payable to, uint256 amount, address token)
        internal
    {
        if (amount == 0) return;

        if (token == address(0)) {
            (bool success, ) = to.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            require(
                IERC20(token).transfer(to, amount),
                "Token transfer failed"
            );
        }
    }

    function _getUsdValue(address token, uint256 amount)
        internal
        view
        returns (uint256)
    {
        if (priceOracle == address(0) || amount == 0) return 0;

        (bool success, bytes memory data) = priceOracle.staticcall(
            abi.encodeWithSignature("getValueInUSD(address,uint256)", token, amount)
        );

        if (success && data.length >= 32) {
            return abi.decode(data, (uint256));
        }
        return 0;
    }

    // 接收 ETH
    receive() external payable {}
}
