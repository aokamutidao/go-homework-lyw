# 07 - EVM 执行层

> 返回: [[Go-Ethereum 核心功能与架构设计研究作业]] | 上一章: [[06-MPT状态存储]] | 下一章: [[08-共识算法]]

## 7.1 EVM 概述

**EVM (Ethereum Virtual Machine)** 是以太坊的智能合约执行引擎，是一个基于栈的虚拟机。

```
EVM 核心特性:
├── 基于栈 (Stack-based) - 操作数栈架构
├── 256 位字长 - 适配加密操作
├── 图灵完备 - 支持任意计算
├── 确定性 - 相同输入产生相同输出
├── 隔离执行 - 与宿主环境隔离
└── Gas 计费 - 防止无限循环
```

## 7.2 EVM 架构

```
                    EVM 执行架构
    ┌─────────────────────────────────────────┐
    │              EVM (core/vm/)              │
    ├─────────────────────────────────────────┤
    │                                          │
    │  ┌───────────────────────────────────┐  │
    │  │           Runtime                  │  │
    │  │  - 合约创建 (CREATE)               │  │
    │  │  - 合约调用 (CALL)                 │  │
    │  │  - 字节码解释                      │  │
    │  └───────────────────────────────────┘  │
    │                    │                     │
    │                    ▼                     │
    │  ┌───────────────────────────────────┐  │
    │  │         Interpreter                 │  │
    │  │  - 指令解码                        │  │
    │  │  - 操作码执行                      │  │
    │  │  - 栈操作                          │  │
    │  └───────────────────────────────────┘  │
    │                    │                     │
    │          ┌─────────┴─────────┐          │
    │          ▼                   ▼          │
    │  ┌─────────────┐    ┌─────────────────┐ │
    │  │   GasTable  │    │  Precompiled    │ │
    │  │  (费用计算)  │    │  (预编译合约)   │ │
    │  └─────────────┘    └─────────────────┘ │
    │                                          │
    └─────────────────────────────────────────┘
```

## 7.3 执行上下文

### EVM 结构

```go
// core/vm/evm.go

type EVM struct {
    // 执行环境
    Context  Context        // 区块上下文
    StateDB  StateDB        // 状态数据库

    // 虚拟机状态
    stack   *Stack          // 操作数栈
    memory  *Memory         // 内存
    contract *Contract      // 当前合约

    // 配置
    Config  Config          // VM 配置
    chainConfig *params.ChainConfig // 链配置

    // 状态
    abort   bool            // 中止标志
    callGas uint64          // 调用 Gas 剩余
}
```

### Context (执行上下文)

```go
// core/vm/evm.go

type Context struct {
    // 区块信息
    CanTransfer CanTransferFunc
    Transfer    TransferFunc
    GetHash     GetHashFunc

    // 区块属性
    Coinbase    common.Address    // 矿工地址
    GasLimit    uint64            // 区块 Gas 上限
    BlockNumber *big.Int          // 区块高度
    Time        *big.Int          // 时间戳
    Difficulty  *big.Int          // 难度值
    BaseFee     *big.Int          // 基础费用 (EIP-1559)

    // 随机数 (合并后)
    Random *common.Hash
}
```

## 7.4 操作码 (Opcodes)

### 操作码分类

```
操作码分类:

┌────────────────────────────────────────────────────────┐
│  算术运算 (Arithmetic)                                  │
│  ADD, SUB, MUL, DIV, MOD, SDIV, SMOD,                  │
│  ADDMOD, MULLMOD, EXP, SIGNEXTEND                      │
├────────────────────────────────────────────────────────┤
│  逻辑运算 (Logical)                                     │
│  LT, GT, SLT, SGT, EQ, ISZERO, AND, OR, XOR, NOT       │
├────────────────────────────────────────────────────────┤
│  密码学 (Cryptographic)                                 │
│  SHA3, SHA3_256                                        │
├────────────────────────────────────────────────────────┤
│  环境信息 (Environmental)                               │
│  ADDRESS, BALANCE, ORIGIN, CALLER, CALLVALUE,          │
│  CALLDATASIZE, CALLDATALOAD, CALLDATACOPY,             │
│  CODESIZE, CODECOPY, GASPRICE, EXTCODESIZE,            │
│  EXTCODEHASH, RETURNDATASIZE, RETURNDATACOPY           │
├────────────────────────────────────────────────────────┤
│  存储操作 (Storage)                                     │
│  SLOAD, SSTORE                                          │
├────────────────────────────────────────────────────────┤
│  区块信息 (Block)                                       │
│  COINBASE, TIMESTAMP, NUMBER, DIFFICULTY, GASLIMIT,    │
│  CHAINID, BASEFEE                                      │
├────────────────────────────────────────────────────────┤
│  流程控制 (Control Flow)                                │
│  STOP, RETURN, REVERT, INVALID, LOG0-5,                │
│  JUMP, JUMPI, PC, JUMPDEST                             │
├────────────────────────────────────────────────────────┤
│  栈操作 (Stack)                                         │
│  PUSH1-32, DUP1-16, SWAP1-16, POP                      │
├────────────────────────────────────────────────────────┤
│  系统操作 (System)                                      │
│  CREATE, CREATE2, CALL, CALLCODE, DELEGATECALL,        │
│  STATICCALL, RETURN, REVERT, SELFDESTRUCT              │
└────────────────────────────────────────────────────────┘
```

### Gas 消耗

```go
// core/vm/gas_table.go

// 基础 Gas 费用
const (
    GasStep          uint64 = 2       // 基础指令费用
    GasFastStep      uint64 = 3       // 快速指令费用
    GasMidStep       uint64 = 5       // 中速指令费用
    GasSlowStep      uint64 = 8       // 慢速指令费用
    GasExtStep       uint64 = 20      // 扩展操作费用
)

// 存储 Gas
const (
    GasStorageLoad   uint64 = 200     // SLOAD
    GasStorageSet    uint64 = 20000   // SSTORE (新存储)
    GasStorageUpdate uint64 = 5000    // SSTORE (更新)
    GasStorageClear  uint64 = -15000  // SSTORE (清除，退款)
)

// 计算 Gas 示例
func gasSStore(evm *EVM, contract *Contract, stack *Stack, mem *Memory, memorySize uint64) (uint64, error) {
    var (
        gas    uint64
        key    = stack.peek()
        value  = stack.peek()
    )

    // 获取当前存储值
    currentValue := evm.StateDB.GetState(contract.Address(), key)

    if currentValue == value {
        // 值为空且设置为非空，费用较低
        if currentValue == (common.Hash{}) && value != (common.Hash{}) {
            return GasStorageSet, nil
        }
        // 值未改变，费用最低
        return GasWarmAccess, nil
    }

    // 值改变，费用较高
    return GasStorageUpdate, nil
}
```

## 7.5 合约执行流程

### CREATE - 创建合约

```
                    CREATE 执行流程
    ┌─────────────────────────────────────────┐
    │                                          │
    │  1. 计算新地址                           │
    │     address = keccak256(creator, nonce) │
    │                                          │
    │  2. 检查地址是否已存在                   │
    │                                          │
    │  3. 创建账户                             │
    │     - 设置 nonce = 1                    │
    │     - 设置 codeHash = empty             │
    │     - 初始化余额                        │
    │                                          │
    │  4. 执行初始化代码                       │
    │     - 创建子 EVM                        │
    │     - 执行字节码                        │
    │     - 收集返回数据                      │
    │                                          │
    │  5. 存储代码                             │
    │     - 将返回数据保存为合约代码           │
    │     - 设置 codeHash                    │
    │                                          │
    │  6. 返回地址                             │
    │     - 将新地址压入栈                     │
    │                                          │
    └─────────────────────────────────────────┘
```

### CALL - 调用合约

```
                    CALL 执行流程
    ┌─────────────────────────────────────────┐
    │                                          │
    │  1. 参数验证                             │
    │     - 检查 Gas 限制                     │
    │     - 检查余额                          │
    │                                          │
    │  2. 转账                                │
    │     - 从调用者转 ETH 到被调合约          │
    │                                          │
    │  3. 创建子上下文                         │
    │     - 保存当前状态                      │
    │     - 准备新状态                        │
    │                                          │
    │  4. 执行被调合约                         │
    │     - 加载被调合约代码                   │
    │     - 执行字节码                        │
    │                                          │
    │  5. 处理返回值                           │
    │     - 收集返回数据                      │
    │     - 存储到内存                        │
    │                                          │
    │  6. 恢复状态                            │
    │     - 回滚未提交的更改                  │
    │                                          │
    └─────────────────────────────────────────┘
```

## 7.6 预编译合约

```
预编译合约 (Precompiled Contracts):

地址 0x01 - ecrecover      - ECDSA 恢复
地址 0x02 - sha256         - SHA-256 哈希
地址 0x03 - ripemd160      - RIPEMD-160 哈希
地址 0x04 - identity       - 身份函数 (内存复制)
地址 0x05 - modexp         - 模幂运算 (EIP-198)
地址 0x06 - addmod         - 模加法 (保留)
地址 0x07 - mulmod         - 模乘法 (保留)
地址 0x08 - sedata         - 签名数据 (保留)
地址 0x09 - bn128Add       - BN128 加法 (EIP-196)
地址 0x0a - bn128Mul       - BN128 乘法 (EIP-196)
地址 0x0b - bn128Pair      - BN128 配对 (EIP-197)
地址 0x0c - pointHash      - 椭圆曲线哈希 (EIP-2537)

特点:
├── 固定 Gas 费用
├── 原生代码实现 (Go)
├── 比 EVM 字节码高效
└── 用于加密操作
```

```go
// core/vm/contracts.go

// ecrecover 实现
func runEcrecover(c *Contract, evm *EVM) ([]byte, error) {
    // 从输入中提取 r, s, v
    // 恢复公钥
    // 计算地址
    // 返回地址
}

// sha256 实现
func runSha256(c *Contract, evm *EVM) ([]byte, error) {
    // 调用 Go 的 sha256 实现
    // 返回哈希结果
}
```

## 7.7 指令解释器

```go
// core/vm/instructions.go

// run 执行单个操作码
func run(pc *uint64, contract *Contract, evm *EVM) error {
    op := contract.GetOp(pc)

    switch op {
    // 算术运算
    case ADD:
        x, y := stack.pop(), stack.pop()
        stack.push(new(big.Int).Add(x, y))
    case SUB:
        x, y := stack.pop(), stack.pop()
        stack.push(new(big.Int).Sub(x, y))
    case MUL:
        x, y := stack.pop(), stack.pop()
        stack.push(new(big.Int).Mul(x, y))
    case DIV:
        x, y := stack.pop(), stack.pop()
        stack.push(new(big.Int).Div(x, y))

    // 存储操作
    case SLOAD:
        key := stack.pop()
        value := evm.StateDB.GetState(contract.Address(), key)
        stack.push(value)
    case SSTORE:
        key, value := stack.pop(), stack.pop()
        evm.StateDB.SetState(contract.Address(), key, value)

    // 合约调用
    case CALL:
        // 实现参见 call.go
        return opCall(pc, contract, evm)
    case CREATE:
        // 实现参见 create.go
        return opCreate(pc, contract, evm)

    // ... 更多操作码
    }

    // Gas 扣除
    contract.Gas -= cost

    // PC 递增
    *pc++

    return nil
}
```

## 7.8 异常处理

```
                    EVM 异常类型

1. OutOfGas
   └── Gas 耗尽

2. StackOverflow
   └── 栈超过 1024 层

3. StackUnderflow
   └── 栈操作需要更多元素

4. InvalidJump
   └── 跳转目标不是 JUMPDEST

5. InvalidOpcode
   └── 未知操作码

6. Revert
   └── 显式回滚 (不消耗 Gas)

7. WriteProtection
   └── 静态调用中修改状态
```

---

**下一步**: 继续阅读 [[08-共识算法]] 了解区块生成机制
