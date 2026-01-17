/**
 * UUPS 升级脚本
 * 将 AuctionV1 升级到 AuctionV2
 */

const { ethers, upgrades } = require("hardhat");

async function main() {
    console.log("开始升级 Auction 合约...\n");

    // 获取部署账户
    const [deployer] = await ethers.getSigners();
    console.log(`操作账户: ${deployer.address}\n`);

    // 旧合约地址（如果有参数则使用，否则从部署文件读取）
    const auctionAddress = process.env.AUCTION_PROXY_ADDRESS;
    if (!auctionAddress) {
        throw new Error("请设置 AUCTION_PROXY_ADDRESS 环境变量");
    }

    console.log(`当前代理地址: ${auctionAddress}`);

    // 获取当前实现版本
    const currentImplementation = await upgrades.erc1967.getImplementationAddress(auctionAddress);
    console.log(`当前实现地址: ${currentImplementation}\n`);

    // 部署新版本
    console.log("部署 AuctionV2...");
    const AuctionV2 = await ethers.getContractFactory("AuctionV2");
    const auctionV2 = await upgrades.upgradeProxy(auctionAddress, AuctionV2);

    console.log(`升级成功！`);
    console.log(`新实现地址: ${await upgrades.erc1967.getImplementationAddress(auctionAddress)}`);

    // 初始化 V2 新功能
    console.log("\n初始化 V2 动态手续费配置...");
    const minFee = ethers.utils.parseEther("0.02");    // 2%
    const maxFee = ethers.utils.parseEther("0.03");    // 3%
    const threshold = ethers.utils.parseEther("5");     // 5 ETH
    const multiplier = ethers.utils.parseEther("0.001"); // 0.1%

    await auctionV2.initializeV2(minFee, maxFee, threshold, multiplier);
    console.log("动态手续费配置已初始化");

    console.log(`\n当前版本: ${await auctionV2.version()}`);
    console.log("\n升级完成！");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
