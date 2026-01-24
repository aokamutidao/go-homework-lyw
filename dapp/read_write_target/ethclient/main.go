package main

import (
	"context"
	"fmt"
	"log"
	"math/big"
	"os"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
)

func main() {
	// Sepolia 测试网络 RPC 地址
	rpcURL := "https://sepolia.infura.io/v3/16c6eeef1ca84f6b8833e5bd15a49660"

	// 连接以太坊客户端
	client, err := ethclient.Dial(rpcURL)
	if err != nil {
		log.Fatalf("Failed to connect to Ethereum client: %v", err)
	}
	defer client.Close()

	fmt.Println("成功连接到 Sepolia 测试网络!")
	fmt.Println("================================")

	// 查询最新区块
	queryBlock(client)

	fmt.Println("================================")

	// 发送交易
	sendTransaction(client)
}

// queryBlock 查询指定区块信息
func queryBlock(client *ethclient.Client) {
	ctx := context.Background()

	// 获取最新区块号
	blockNumber, err := client.BlockNumber(ctx)
	if err != nil {
		log.Fatalf("Failed to get block number: %v", err)
	}
	fmt.Printf("最新区块号: %d\n\n", blockNumber)

	// 查询最新区块信息
	block, err := client.BlockByNumber(ctx, big.NewInt(int64(blockNumber)))
	if err != nil {
		log.Fatalf("Failed to get block: %v", err)
	}

	// 输出区块信息
	fmt.Println("=== 区块信息 ===")
	fmt.Printf("区块哈希:     %s\n", block.Hash().Hex())
	fmt.Printf("父区块哈希:   %s\n", block.ParentHash().Hex())
	fmt.Printf("区块号:       %d\n", block.Number().Int64())
	fmt.Printf("时间戳:       %d\n", block.Time())
	fmt.Printf("难度值:       %d\n", block.Difficulty().Uint64())
	fmt.Printf("Gas Limit:    %d\n", block.GasLimit())
	fmt.Printf("Gas Used:     %d\n", block.GasUsed())
	fmt.Printf("交易数量:     %d\n", len(block.Transactions()))
	fmt.Printf("区块大小:     %d bytes\n", block.Size())

	// 如果有交易，列出前3笔交易
	if len(block.Transactions()) > 0 {
		fmt.Println("\n=== 前3笔交易 ===")
		count := 3
		if len(block.Transactions()) < 3 {
			count = len(block.Transactions())
		}
		for i := 0; i < count; i++ {
			tx := block.Transactions()[i]
			fmt.Printf("交易 %d: %s\n", i+1, tx.Hash().Hex())
		}
	}
}

// sendTransaction 发送一笔简单的以太币转账交易
func sendTransaction(client *ethclient.Client) {
	ctx := context.Background()

	// === 从环境变量获取私钥 ===
	privateKeyHex := os.Getenv("PRIVATE_KEY")

	// 接收方地址
	toAddress := common.HexToAddress("0x742d35Cc6634C0532925a3b844Bc9e7595f8bBf5")

	// 转账金额 (0.01 ETH)
	amount := new(big.Int).Mul(big.NewInt(1), big.NewInt(10000000000000000)) // 0.01 ETH in wei
	// ========================================

	// 检查私钥是否已配置
	if privateKeyHex == "" {
		fmt.Println("\n=== 发送交易 ===")
		fmt.Println("❌ 未找到私钥!")
		fmt.Println("\n请设置 PRIVATE_KEY 环境变量:")
		fmt.Println("  export PRIVATE_KEY='0x你的私钥'")
		fmt.Println("\n或临时运行:")
		fmt.Println("  PRIVATE_KEY='0x你的私钥' ./ethclient")
		fmt.Println("\n提示: 可以从 MetaMask 导出私钥 (设置 -> 账户详情 -> 导出私钥)")
		return
	}

	// 解析私钥
	privateKey, err := crypto.HexToECDSA(privateKeyHex[2:]) // 去掉0x前缀
	if err != nil {
		log.Fatalf("Failed to parse private key: %v", err)
	}

	// 获取发送方地址
	fromAddress := crypto.PubkeyToAddress(privateKey.PublicKey)

	fmt.Println("\n=== 发送交易 ===")
	fmt.Printf("发送方: %s\n", fromAddress.Hex())
	fmt.Printf("接收方: %s\n", toAddress.Hex())
	fmt.Printf("金额:   %s ETH\n", new(big.Float).Quo(new(big.Float).SetInt(amount), new(big.Float).SetInt(big.NewInt(1e18))).String())

	// 获取发送方的 nonce
	nonce, err := client.NonceAt(ctx, fromAddress, nil)
	if err != nil {
		log.Fatalf("Failed to get nonce: %v", err)
	}
	fmt.Printf("Nonce:  %d\n", nonce)

	// 获取当前 gas 价格
	gasPrice, err := client.SuggestGasPrice(ctx)
	if err != nil {
		log.Fatalf("Failed to suggest gas price: %v", err)
	}
	fmt.Printf("Gas Price: %s Gwei\n", new(big.Float).Quo(new(big.Float).SetInt(gasPrice), new(big.Float).SetInt(big.NewInt(1e9))).String())

	// 获取链 ID
	chainID, err := client.ChainID(ctx)
	if err != nil {
		log.Fatalf("Failed to get chain ID: %v", err)
	}
	fmt.Printf("Chain ID: %d\n", chainID.Int64())

	// 创建交易 (使用动态费用交易类型以支持 EIP-1559)
	data := make([]byte, 0)
	tx := types.NewTx(&types.DynamicFeeTx{
		ChainID:   chainID,
		Nonce:     nonce,
		Gas:       21000, // 标准 ETH 转账的 gas limit
		GasFeeCap: gasPrice,
		GasTipCap: big.NewInt(1), // 小费
		To:        &toAddress,
		Value:     amount,
		Data:      data,
	})

	// 对交易进行签名
	signer := types.NewLondonSigner(chainID)
	signedTx, err := types.SignTx(tx, signer, privateKey)
	if err != nil {
		log.Fatalf("Failed to sign tx: %v", err)
	}

	// 发送交易到网络
	err = client.SendTransaction(ctx, signedTx)
	if err != nil {
		log.Fatalf("Failed to send tx: %v", err)
	}

	fmt.Printf("\n✅ 交易发送成功!\n")
	fmt.Printf("交易哈希: %s\n", signedTx.Hash().Hex())
	fmt.Printf("查看交易: https://sepolia.etherscan.io/tx/%s\n", signedTx.Hash().Hex())
}
