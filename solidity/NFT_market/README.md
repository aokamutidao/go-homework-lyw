# NFT Auction Market

基于 Hardhat 开发的 NFT 拍卖市场合约，支持 ETH 和 ERC20 出价，集成 Chainlink 预言机价格计算，使用 UUPS 代理模式实现合约升级。

## 功能特性

- **NFT 拍卖**: 支持创建拍卖、竞价、结算全流程
- **多币种出价**: 支持 ETH 和 ERC20 代币出价
- **Chainlink 预言机**: 实时获取价格，将出价转换为 USD
- **UUPS 代理升级**: 支持平滑升级到新版本
- **灵活的手续费**: 可配置的手续费机制

## 项目结构

```
NFT_market/
├── contracts/
│   ├── AuctionV1.sol        # 拍卖合约 V1 (UUPS)
│   ├── AuctionV2.sol        # 拍卖合约 V2 (动态手续费)
│   ├── MockNFT.sol          # 测试用 NFT 合约
│   ├── MockERC20.sol        # 测试用 ERC20 合约
│   ├── PriceOracle.sol      # Chainlink 价格预言机
│   ├── MockPriceFeed.sol    # 测试用 PriceFeed
│   └── MockPriceOracle.sol  # 测试用 PriceOracle
├── test/
│   └── Auction.test.js      # 单元测试
├── scripts/
│   ├── deploy.js            # 本地部署脚本
│   ├── deploy-sepolia.js    # Sepolia 部署脚本
│   └── upgrade.js           # UUPS 升级脚本
├── hardhat.config.js        # Hardhat 配置
└── package.json
```

## 快速开始

### 1. 安装依赖

```bash
npm install
```

### 2. 配置环境变量

```bash
cp .env.example .env
# 编辑 .env 文件，填入 RPC URL 和私钥
```

### 3. 编译合约

```bash
npm run compile
```

### 4. 运行测试

```bash
npm run test
```

### 5. 本地部署

```bash
npx hardhat run scripts/deploy.js --network hardhat
```

### 6. 部署到 Sepolia

```bash
npm run deploy:sepolia
```

### 7. 升级合约

```bash
# 设置环境变量
export AUCTION_PROXY_ADDRESS=0x...

# 执行升级
npx hardhat run scripts/upgrade.js --network sepolia
```

## 合约说明

### AuctionV1

主要拍卖合约，包含以下功能：

- `createAuction()`: 创建拍卖
- `bidWithEth()`: ETH 出价
- `bidWithToken()`: ERC20 出价
- `settleAuction()`: 结算拍卖
- `cancelAuction()`: 取消拍卖（无出价时）

### PriceOracle

Chainlink 价格预言机封装：

- `getPrice()`: 获取代币美元价格
- `getValueInUSD()`: 计算代币价值的美元金额
- `getAmountFromUSD()`: 将美元转换为代币数量

### UUPS 升级

使用 OpenZeppelin UUPS 代理模式：

1. 部署新版本合约
2. 调用 `upgradeProxy()` 执行升级
3. 初始化新功能

## 测试覆盖

- 合约部署测试
- 创建拍卖测试
- ETH/ERC20 出价测试
- 拍卖结算测试
- UUPS 升级测试
- 价格预言机测试

## Chainlink Price Feed

### Sepolia 测试网地址

- ETH/USD: `0x694AA1769357215DE4FAC081bf1f309aDC325306`
- LINK/USD: `0xc59E3633BAAC7949054ecF67bfbE17F056c9D407`

### Mainnet 地址

请参考 [Chainlink Price Feeds 地址](https://docs.chain.link/data-feeds/price-feeds/addresses)

## 手续费说明

默认手续费: 2.5%

- 卖家获得: 97.5%
- 协议获得: 2.5%

## 注意事项

1. **私钥安全**: 绝不要将私钥提交到代码仓库
2. **测试网优先**: 务必先在测试网验证合约
3. **充分测试**: 部署前编写完整的测试用例
4. **审计**: 生产环境部署前建议进行安全审计

## 许可

MIT License

## 测试报告
![alt text](image.png)

### 部署地址
开始部署 NFT Auction Market 合约...

部署账户: 0x56c2A57C6E42bFd4e6724ff4853EB6025F667A07
账户余额: 270914664699855537

1. 部署 MockNFT 合约...
MockNFT 部署地址: 0xba88fD2Fe6F5DCEb21270c2e65625893c0c9e3d3

2. 部署 MockERC20 合约...
MockERC20 部署地址: 0x8749Eb96B370e0Aba28AE8f2082a820604CeDCC2

3. 部署 PriceOracle 合约...
PriceOracle 部署地址: 0xece8BCEfbB62f461B8150dc99936CEa54DdA1D14

4. 部署 AuctionV1 合约 (UUPS Proxy)...
AuctionV1 部署地址: 0x30a252E03f8c53aC9A451d6E426b03Ca8f71CEc8
AuctionV1 Proxy Admin: 0x0000000000000000000000000000000000000000

5. 配置合约...
已添加 0x8749Eb96B370e0Aba28AE8f2082a820604CeDCC2 到支持代币列表
