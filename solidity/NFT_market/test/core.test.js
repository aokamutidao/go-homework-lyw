const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
require("dotenv").config();

describe("NFT Auction Market - Core Tests", function () {
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
    });

    describe("Price Oracle Integration", function () {
        it("Should return correct USD value", async function () {
            await mockPriceOracle.updatePrice(ethers.constants.AddressZero, 3000e8);

            const ethAmount = ethers.utils.parseEther("1");
            const usdValue = await mockPriceOracle.getValueInUSD(ethers.constants.AddressZero, ethAmount);

            expect(usdValue).to.equal(ethers.utils.parseEther("3000"));
        });

        it("Should get supported feeds", async function () {
            const count = await mockPriceOracle.getSupportedTokenCount();
            expect(count).to.equal(2); // ETH and LINK

            const ethName = await mockPriceOracle.getFeedName(ethers.constants.AddressZero);
            expect(ethName).to.equal("ETH/USD");
        });
    });
});
