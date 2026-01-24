package main

import (
	"context"
	"fmt"
	"log"
	"math/big"
	"os"
	"strings"
	"time"

	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"

	counter "gen_contract_code/counter"
)

const (
	chainID = 11155111 // Sepolia chain ID
	envFile = ".env"
)

// loadEnv reads the .env file and returns a map of environment variables
func loadEnv() (map[string]string, error) {
	data, err := os.ReadFile(envFile)
	if err != nil {
		return nil, fmt.Errorf("failed to read .env file: %v", err)
	}

	env := make(map[string]string)
	lines := strings.Split(string(data), "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		parts := strings.SplitN(line, "=", 2)
		if len(parts) == 2 {
			env[strings.TrimSpace(parts[0])] = strings.TrimSpace(parts[1])
		}
	}
	return env, nil
}

// saveEnv saves the environment variables to .env file
func saveEnv(env map[string]string) error {
	var lines []string
	lines = append(lines, "# Sepolia RPC URL")
	lines = append(lines, "RPC_URL="+env["RPC_URL"])
	lines = append(lines, "")
	lines = append(lines, "# Your private key (without 0x prefix)")
	lines = append(lines, "PRIVATE_KEY="+env["PRIVATE_KEY"])
	lines = append(lines, "")
	lines = append(lines, "# Counter contract address (auto-filled after first deployment)")
	lines = append(lines, "CONTRACT_ADDRESS="+env["CONTRACT_ADDRESS"])

	content := strings.Join(lines, "\n") + "\n"
	return os.WriteFile(envFile, []byte(content), 0644)
}

func main() {
	// Load configuration from .env file
	env, err := loadEnv()
	if err != nil {
		log.Fatalf("Failed to load .env file: %v", err)
	}

	rpcURL := env["RPC_URL"]
	privateKey := env["PRIVATE_KEY"]
	contractAddressStr := env["CONTRACT_ADDRESS"]

	// Check if private key is set
	if privateKey == "" {
		fmt.Println("Error: Please set PRIVATE_KEY in .env file")
		fmt.Println("Get Sepolia ETH from: https://sepoliafaucet.com/")
		os.Exit(1)
	}

	// Connect to Sepolia
	client, err := ethclient.Dial(rpcURL)
	if err != nil {
		log.Fatalf("Failed to connect to Sepolia: %v", err)
	}
	defer client.Close()

	fmt.Println("✅ Connected to Sepolia test network")
	fmt.Printf("Chain ID: %d\n", chainID)

	// Parse private key
	key, err := crypto.HexToECDSA(privateKey)
	if err != nil {
		log.Fatalf("Failed to parse private key: %v", err)
	}

	// Get account address
	fromAddress := crypto.PubkeyToAddress(key.PublicKey)
	fmt.Printf("Account: %s\n", fromAddress.Hex())

	// Create auth options
	auth, err := bind.NewKeyedTransactorWithChainID(key, big.NewInt(chainID))
	if err != nil {
		log.Fatalf("Failed to create transactor: %v", err)
	}

	nonce, err := client.PendingNonceAt(context.Background(), fromAddress)
	if err != nil {
		log.Fatalf("Failed to get nonce: %v", err)
	}
	auth.Nonce = big.NewInt(int64(nonce))

	gasPrice, err := client.SuggestGasPrice(context.Background())
	if err != nil {
		log.Fatalf("Failed to get gas price: %v", err)
	}
	auth.GasPrice = gasPrice

	// Determine if we need to deploy or use existing contract
	var contractAddress common.Address
	var counterContract *counter.Counter

	if contractAddressStr == "" {
		// Deploy new contract
		fmt.Println("\n🚀 Deploying Counter contract to Sepolia...")

		address, tx, _, err := counter.DeployCounter(auth, client)
		if err != nil {
			log.Fatalf("Failed to deploy contract: %v", err)
		}

		contractAddress = address

		fmt.Printf("✅ Contract deployed at: %s\n", address.Hex())
		fmt.Printf("   Transaction hash: %s\n", tx.Hash().Hex())
		fmt.Println("   Waiting for confirmation...")

		// Wait for deployment confirmation
		for {
			_, isPending, err := client.TransactionByHash(context.Background(), tx.Hash())
			if err != nil {
				time.Sleep(2 * time.Second)
				continue
			}
			if !isPending {
				break
			}
			time.Sleep(2 * time.Second)
		}

		receipt, err := client.TransactionReceipt(context.Background(), tx.Hash())
		if err == nil && receipt != nil {
			fmt.Printf("   Block number: %d\n", receipt.BlockNumber.Uint64())
			fmt.Printf("   Gas used: %d\n", receipt.GasUsed)
		}

		// Save contract address to .env
		env["CONTRACT_ADDRESS"] = contractAddress.Hex()
		if err := saveEnv(env); err != nil {
			log.Printf("Warning: Failed to save CONTRACT_ADDRESS to .env: %v", err)
		} else {
			fmt.Println("   Contract address saved to .env")
		}
	} else {
		// Use existing contract
		contractAddress = common.HexToAddress(contractAddressStr)
		fmt.Printf("\n📎 Using existing contract at: %s\n", contractAddressStr)
	}

	// Load contract
	counterContract, err = counter.NewCounter(contractAddress, client)
	if err != nil {
		log.Fatalf("Failed to load contract: %v", err)
	}

	// Call getCount to get initial value
	fmt.Println("\n📊 Reading counter value...")

	opts := &bind.CallOpts{Pending: false}
	count, err := counterContract.GetCount(opts)
	if err != nil {
		log.Fatalf("Failed to get count: %v", err)
	}
	fmt.Printf("   Current count: %s\n", count.String())

	// Increment counter (transaction)
	fmt.Println("\n🔼 Calling increment()...")

	nonce2, _ := client.PendingNonceAt(context.Background(), auth.From)
	auth.Nonce = big.NewInt(int64(nonce2))

	tx, err := counterContract.Increment(auth)
	if err != nil {
		log.Fatalf("Failed to call increment: %v", err)
	}

	fmt.Printf("   Transaction hash: %s\n", tx.Hash().Hex())

	time.Sleep(5 * time.Second)

	count, err = counterContract.GetCount(opts)
	if err != nil {
		log.Fatalf("Failed to get count: %v", err)
	}
	fmt.Printf("   New count: %s\n", count.String())

	// Increment again
	fmt.Println("\n🔼 Calling increment() again...")

	nonce3, _ := client.PendingNonceAt(context.Background(), auth.From)
	auth.Nonce = big.NewInt(int64(nonce3))

	tx, err = counterContract.Increment(auth)
	if err != nil {
		log.Fatalf("Failed to call increment: %v", err)
	}

	fmt.Printf("   Transaction hash: %s\n", tx.Hash().Hex())

	time.Sleep(5 * time.Second)

	count, err = counterContract.GetCount(opts)
	if err != nil {
		log.Fatalf("Failed to get count: %v", err)
	}
	fmt.Printf("   New count: %s\n", count.String())

	fmt.Println("\n✅ Demo completed successfully!")
	fmt.Printf("Contract address: %s\n", contractAddress.Hex())
}
