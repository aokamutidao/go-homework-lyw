const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
require("dotenv").config();

describe("NFT Auction Market", function () {
    let mockNFT;
    let mockERC20;
    let mockPriceOracle;
    let auction;
    let owner;
    let seller;
    let buyer1;
    let buyer2;
    let feeRecipient;

    let AUCTION_DURATION;
    let STARTING_PRICE;
    let FEE_PERCENT;

    beforeEach(async function () {
        AUCTION_DURATION = 24 * 60 * 60; // 24 hours
        STARTING_PRICE = ethers.utils.parseEther("1");
        FEE_PERCENT = ethers.utils.parseEther("0.025"); // 2.5%
        [owner, seller, buyer1, buyer2, feeRecipient] = await ethers.getSigners();

        // 部署 Mock NFT
        const MockNFT = await ethers.getContractFactory("MockNFT");
        mockNFT = await MockNFT.deploy();
        await mockNFT.deployed();

        // 部署 Mock ERC20
        const MockERC20 = await ethers.getContractFactory("MockERC20");
        mockERC20 = await MockERC20.deploy("Test Token", "TEST", 18);
        await mockERC20.deployed();

        // 部署 Mock Price Oracle
        const MockPriceOracle = await ethers.getContractFactory("MockPriceOracle");
        mockPriceOracle = await MockPriceOracle.deploy();
        await mockPriceOracle.deployed();

        // 部署 Auction 合约
        const Auction = await ethers.getContractFactory("AuctionV1");
        auction = await upgrades.deployProxy(Auction, [
            mockPriceOracle.address,
            feeRecipient.address,
            FEE_PERCENT
        ], { initializer: 'initialize' });
        await auction.deployed();

        // 设置支持的代币
        await auction.setSupportedToken(mockERC20.address, true);

        // 铸造 NFT 给卖家
        await mockNFT.safeMint(seller.address, "ipfs://tokenURI1");
        await mockNFT.safeMint(seller.address, "ipfs://tokenURI2");

        // 铸造 ERC20 给买家
        await mockERC20.mint(buyer1.address, ethers.utils.parseEther("100"));
        await mockERC20.mint(buyer2.address, ethers.utils.parseEther("100"));

        // 授权 NFT 给拍卖合约
        await mockNFT.connect(seller).setApprovalForAll(auction.address, true);

        // 授权 ERC20
        await mockERC20.connect(buyer1).approve(auction.address, ethers.constants.MaxUint256);
        await mockERC20.connect(buyer2).approve(auction.address, ethers.constants.MaxUint256);
    });

    describe("Deployment", function () {
        it("Should set correct initial values", async function () {
            expect(await auction.owner()).to.equal(owner.address);
            expect(await auction.auctionCount()).to.equal(0);
        });

        it("Should set correct fee config", async function () {
            const config = await auction.feeConfig();
            expect(config.feePercent).to.equal(FEE_PERCENT);
            expect(config.feeRecipient).to.equal(feeRecipient.address);
        });
    });

    describe("Auction Creation", function () {
        it("Should create an auction", async function () {
            const tx = await auction.connect(seller).createAuction(
                mockNFT.address,
                0,  // tokenId
                STARTING_PRICE,
                AUCTION_DURATION,
                ethers.constants.AddressZero  // ETH
            );

            const receipt = await tx.wait();
            const auctionId = receipt.events.find(e => e.event === "AuctionCreated").args.auctionId;

            expect(auctionId).to.equal(1);

            const auctionData = await auction.auctions(1);
            expect(auctionData.seller).to.equal(seller.address);
            expect(auctionData.nftContract).to.equal(mockNFT.address);
            expect(auctionData.tokenId).to.equal(0);
            expect(auctionData.startingPrice).to.equal(STARTING_PRICE);
            expect(auctionData.status).to.equal(1); // Active
        });

        it("Should fail if NFT not approved", async function () {
            await mockNFT.connect(seller).setApprovalForAll(auction.address, false);

            await expect(
                auction.connect(seller).createAuction(
                    mockNFT.address,
                    0,
                    STARTING_PRICE,
                    AUCTION_DURATION,
                    ethers.constants.AddressZero
                )
            ).to.be.revertedWith("NFT not approved");
        });

        it("Should fail with invalid duration", async function () {
            await expect(
                auction.connect(seller).createAuction(
                    mockNFT.address,
                    0,
                    STARTING_PRICE,
                    300,  // less than 1 hour
                    ethers.constants.AddressZero
                )
            ).to.be.revertedWith("Invalid duration");
        });
    });

    describe("Bidding with ETH", function () {
        let auctionId;

        beforeEach(async function () {
            const tx = await auction.connect(seller).createAuction(
                mockNFT.address,
                0,
                STARTING_PRICE,
                AUCTION_DURATION,
                ethers.constants.AddressZero
            );
            const receipt = await tx.wait();
            auctionId = receipt.events.find(e => e.event === "AuctionCreated").args.auctionId;
        });

        it("Should place a bid with ETH", async function () {
            const bidAmount = ethers.utils.parseEther("2");

            await auction.connect(buyer1).bidWithEth(auctionId, { value: bidAmount });

            const auctionData = await auction.auctions(auctionId);
            expect(auctionData.highestBidder).to.equal(buyer1.address);
            expect(auctionData.highestBid).to.equal(bidAmount);
        });

        it("Should refund previous bidder", async function () {
            const bid1 = ethers.utils.parseEther("1");
            const bid2 = ethers.utils.parseEther("3");

            await auction.connect(buyer1).bidWithEth(auctionId, { value: bid1 });
            await auction.connect(buyer2).bidWithEth(auctionId, { value: bid2 });

            const auctionData = await auction.auctions(auctionId);
            expect(auctionData.highestBidder).to.equal(buyer2.address);
            expect(auctionData.highestBid).to.equal(bid2);
        });

        it("Should fail with bid lower than starting price", async function () {
            const bidAmount = ethers.utils.parseEther("0.5");

            await expect(
                auction.connect(buyer1).bidWithEth(auctionId, { value: bidAmount })
            ).to.be.revertedWith("Bid too low");
        });

        it("Should fail when auction ended", async function () {
            // 创建第二个拍卖（使用 tokenId=1）
            await mockNFT.safeMint(seller.address, "ipfs://tokenURI3");

            // 快速测试：创建短时间拍卖
            await auction.connect(seller).createAuction(
                mockNFT.address,
                1,
                STARTING_PRICE,
                3600,  // 1 hour (minimum)
                ethers.constants.AddressZero
            );

            // 等待结束
            await ethers.provider.send("evm_increaseTime", [3601]);
            await ethers.provider.send("evm_mine", []);

            await expect(
                auction.connect(buyer1).bidWithEth(2, { value: ethers.utils.parseEther("2") })
            ).to.be.revertedWith("Auction ended");
        });
    });

    describe("Bidding with ERC20", function () {
        let auctionId;

        beforeEach(async function () {
            const tx = await auction.connect(seller).createAuction(
                mockNFT.address,
                0,
                STARTING_PRICE,
                AUCTION_DURATION,
                mockERC20.address
            );
            const receipt = await tx.wait();
            auctionId = receipt.events.find(e => e.event === "AuctionCreated").args.auctionId;
        });

        it("Should place a bid with ERC20", async function () {
            const bidAmount = ethers.utils.parseEther("2");

            await auction.connect(buyer1).bidWithToken(auctionId, bidAmount);

            const auctionData = await auction.auctions(auctionId);
            expect(auctionData.highestBidder).to.equal(buyer1.address);
            expect(auctionData.highestBid).to.equal(bidAmount);
        });

        it("Should fail with insufficient allowance", async function () {
            await mockERC20.connect(buyer1).approve(auction.address, 0);

            await expect(
                auction.connect(buyer1).bidWithToken(auctionId, ethers.utils.parseEther("2"))
            ).to.be.revertedWith("Insufficient allowance");
        });
    });

    describe("Auction Settlement", function () {
        let auctionId;

        beforeEach(async function () {
            const tx = await auction.connect(seller).createAuction(
                mockNFT.address,
                0,
                STARTING_PRICE,
                AUCTION_DURATION,
                ethers.constants.AddressZero  // 使用 ETH 出价
            );
            const receipt = await tx.wait();
            auctionId = receipt.events.find(e => e.event === "AuctionCreated").args.auctionId;
        });

        it("Should cancel auction if no bids", async function () {
            await ethers.provider.send("evm_increaseTime", [AUCTION_DURATION + 1]);
            await ethers.provider.send("evm_mine", []);

            await auction.connect(seller).settleAuction(auctionId);

            const auctionData = await auction.auctions(auctionId);
            expect(auctionData.status).to.equal(3); // Cancelled

            // NFT 应该退回给卖家
            expect(await mockNFT.ownerOf(0)).to.equal(seller.address);
        });
    });

    describe("UUPS Upgrade", function () {
        it("Should have version function", async function () {
            // V2 版本测试
            const AuctionV2 = await ethers.getContractFactory("AuctionV2");
            const auctionV2 = await AuctionV2.deploy();
            await auctionV2.deployed();

            expect(await auctionV2.version()).to.equal("2.0.0");
        });
    });

    describe("Price Oracle Integration", function () {
        it("Should return correct USD value", async function () {
            // 更新 ETH 价格 (新版本需要 name 参数)
            await mockPriceOracle.updatePrice(ethers.constants.AddressZero, 3000e8);

            const ethAmount = ethers.utils.parseEther("1");
            const usdValue = await mockPriceOracle.getValueInUSD(ethers.constants.AddressZero, ethAmount);

            expect(usdValue).to.equal(ethers.utils.parseEther("3000"));
        });

        it("Should get supported feeds", async function () {
            // 获取支持的代币数量
            const count = await mockPriceOracle.getSupportedTokenCount();
            expect(count).to.equal(2); // ETH and LINK

            // 获取所有支持的 Feed
            const [tokens, names, feeds] = await mockPriceOracle.getAllSupportedFeeds();

            expect(tokens.length).to.equal(2);
            expect(names[0]).to.equal("ETH/USD");
            expect(names[1]).to.equal("LINK/USD");

            // 获取单个代币名称
            const ethName = await mockPriceOracle.getFeedName(ethers.constants.AddressZero);
            expect(ethName).to.equal("ETH/USD");
        });

        it("Should add new price feed", async function () {
            // 添加新的 BTC 价格 Feed
            const btcToken = "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599";
            await mockPriceOracle.setPriceFeed(btcToken, "BTC/USD", 60000e8);

            // 验证添加成功
            const count = await mockPriceOracle.getSupportedTokenCount();
            expect(count).to.equal(3);

            const btcName = await mockPriceOracle.getFeedName(btcToken);
            expect(btcName).to.equal("BTC/USD");
        });
    });

    describe("Fee Configuration", function () {
        it("Should update fee config", async function () {
            const newFee = ethers.utils.parseEther("0.05"); // 5%
            await auction.setFeeConfig(newFee, buyer1.address);

            const config = await auction.feeConfig();
            expect(config.feePercent).to.equal(newFee);
            expect(config.feeRecipient).to.equal(buyer1.address);
        });

        it("Should reject fee > 10%", async function () {
            const tooHighFee = ethers.utils.parseEther("0.15"); // 15%

            await expect(
                auction.setFeeConfig(tooHighFee, feeRecipient.address)
            ).to.be.revertedWith("Fee too high");
        });
    });
});
