/**
 * NFT Auction Market 部署脚本
 * 使用 Hardhat 部署到本地网络或测试网
 */

const { ethers, upgrades } = require("hardhat");

async function main() {
    console.log("开始部署 NFT Auction Market 合约...\n");

    // 获取部署账户
    const [deployer] = await ethers.getSigners();
    console.log(`部署账户: ${deployer.address}`);
    console.log(`账户余额: ${(await ethers.provider.getBalance(deployer.address)).toString()}\n`);

    // 1. 部署 MockNFT
    console.log("1. 部署 MockNFT 合约...");
    const MockNFT = await ethers.getContractFactory("MockNFT");
    const mockNFT = await MockNFT.deploy();
    await mockNFT.deployed();
    console.log(`MockNFT 部署地址: ${mockNFT.address}\n`);

    // 2. 部署 MockERC20
    console.log("2. 部署 MockERC20 合约...");
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    const mockERC20 = await MockERC20.deploy("Test Token", "TEST", 18);
    await mockERC20.deployed();
    console.log(`MockERC20 部署地址: ${mockERC20.address}\n`);

    // 3. 部署 PriceOracle
    console.log("3. 部署 PriceOracle 合约...");
    const PriceOracle = await ethers.getContractFactory("PriceOracle");
    const priceOracle = await PriceOracle.deploy();
    await priceOracle.deployed();
    console.log(`PriceOracle 部署地址: ${priceOracle.address}\n`);

    // 4. 部署 AuctionV1 (UUPS Proxy)
    console.log("4. 部署 AuctionV1 合约 (UUPS Proxy)...");
    const Auction = await ethers.getContractFactory("AuctionV1");

    const FEE_PERCENT = ethers.utils.parseEther("0.025"); // 2.5%
    const feeRecipient = deployer.address;

    const auction = await upgrades.deployProxy(Auction, [
        priceOracle.address,
        feeRecipient,
        FEE_PERCENT
    ], { initializer: 'initialize' });
    await auction.deployed();
    console.log(`AuctionV1 部署地址: ${auction.address}`);
    console.log(`AuctionV1 Proxy Admin: ${await upgrades.erc1967.getAdminAddress(auction.address)}\n`);

    // 5. 配置合约
    console.log("5. 配置合约...");
    await auction.setSupportedToken(mockERC20.address, true);
    console.log(`已添加 ${mockERC20.address} 到支持代币列表\n`);

    // 6. 演示：铸造 NFT 和代币
    console.log("6. 演示铸造...");
    const tokenURI = "ipfs://QmTest123456789";
    await mockNFT.safeMint(deployer.address, tokenURI);
    console.log(`铸造 NFT #0 到 ${deployer.address}`);

    await mockERC20.mint(deployer.address, ethers.utils.parseEther("10000"));
    console.log(`铸造 10000 TEST 到 ${deployer.address}\n`);

    // 7. 打印部署摘要（跳过示例拍卖，可在 UI 中操作）
    console.log("7. 部署完成！\n");
    console.log("=".repeat(50));
    console.log("合约地址:");
    console.log(`  - MockNFT:    ${mockNFT.address}`);
    console.log(`  - MockERC20:  ${mockERC20.address}`);
    console.log(`  - PriceOracle: ${priceOracle.address}`);
    console.log(`  - Auction:    ${auction.address}`);
    console.log("\n提示: 可在 Etherscan 上调用以下函数:");
    console.log("  1. mockNFT.setApprovalForAll(auction.address, true)");
    console.log("  2. auction.createAuction(...)");
    console.log("=".repeat(50));
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
