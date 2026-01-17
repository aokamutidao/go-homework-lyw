/**
 * NFT Auction Market 部署脚本 (Sepolia 测试网)
 */

require("dotenv").config();
const { ethers, upgrades } = require("hardhat");

async function main() {
    console.log("部署到 Sepolia 测试网...\n");

    // RPC 连接检查
    const rpcUrl = process.env.SEPOLIA_RPC_URL;
    if (!rpcUrl) {
        throw new Error("请设置 SEPOLIA_RPC_URL 环境变量");
    }

    // 获取部署账户
    const [deployer] = await ethers.getSigners();
    console.log(`部署账户: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(deployer.address);
    console.log(`账户余额: ${ethers.utils.formatEther(balance)} ETH\n`);

    // 1. 部署 MockNFT (仅用于测试)
    console.log("1. 部署 MockNFT...");
    const MockNFT = await ethers.getContractFactory("MockNFT");
    const mockNFT = await MockNFT.deploy();
    await mockNFT.deployed();
    console.log(`   地址: ${mockNFT.address}\n`);

    // 2. 部署 MockERC20 (仅用于测试)
    console.log("2. 部署 MockERC20...");
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    const mockERC20 = await MockERC20.deploy("Test Token", "TEST", 18);
    await mockERC20.deployed();
    console.log(`   地址: ${mockERC20.address}\n`);

    // 3. 部署 PriceOracle (使用真实 Chainlink 地址)
    console.log("3. 部署 PriceOracle...");
    const PriceOracle = await ethers.getContractFactory("PriceOracle");
    const priceOracle = await PriceOracle.deploy();
    await priceOracle.deployed();
    console.log(`   地址: ${priceOracle.address}\n`);

    // 4. 部署 Auction (UUPS Proxy)
    console.log("4. 部署 AuctionV1 (UUPS Proxy)...");
    const Auction = await ethers.getContractFactory("AuctionV1");

    const FEE_PERCENT = ethers.utils.parseEther("0.025"); // 2.5%
    const feeRecipient = deployer.address;

    const auction = await upgrades.deployProxy(Auction, [
        priceOracle.address,
        feeRecipient,
        FEE_PERCENT
    ], { initializer: 'initialize' });
    await auction.deployed();
    console.log(`   代理地址: ${auction.address}`);
    console.log(`   实现地址: ${await upgrades.erc1967.getImplementationAddress(auction.address)}\n`);

    // 5. 配置
    console.log("5. 配置合约...");
    await auction.setSupportedToken(mockERC20.address, true);
    console.log(`   已添加 ERC20 支持\n`);

    // 6. 验证 (如果配置了 Etherscan API Key)
    if (process.env.ETHERSCAN_API_KEY) {
        console.log("6. 验证合约...");
        try {
            await hre.run("verify:verify", {
                address: mockNFT.address,
                constructorArguments: [],
            });
            console.log("   MockNFT 验证成功");
        } catch (e) {
            console.log("   MockNFT 验证失败:", e.message);
        }

        try {
            await hre.run("verify:verify", {
                address: mockERC20.address,
                constructorArguments: ["Test Token", "TEST", 18],
            });
            console.log("   MockERC20 验证成功");
        } catch (e) {
            console.log("   MockERC20 验证失败:", e.message);
        }

        try {
            await hre.run("verify:verify", {
                address: auction.address,
            });
            console.log("   Auction 验证成功");
        } catch (e) {
            console.log("   Auction 验证失败:", e.message);
        }
    }

    // 打印部署摘要
    console.log("\n" + "=".repeat(60));
    console.log("部署完成！\n");
    console.log("合约地址 (Sepolia):");
    console.log(`  MockNFT:    ${mockNFT.address}`);
    console.log(`  MockERC20:  ${mockERC20.address}`);
    console.log(`  PriceOracle: ${priceOracle.address}`);
    console.log(`  Auction:    ${auction.address}`);
    console.log("\n请更新 .env 文件中的合约地址以便前端使用");
    console.log("=".repeat(60));
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
