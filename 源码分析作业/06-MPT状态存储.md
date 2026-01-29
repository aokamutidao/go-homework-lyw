# 06 - MPT 默克尔树实现

> 返回: [[Go-Ethereum 核心功能与架构设计研究作业]] | 上一章: [[05-区块链同步协议]] | 下一章: [[07-EVM执行层]]

## 6.1 MPT 概述

**MPT (Merkle Patricia Trie)** 是以太坊用于存储世界状态的数据结构，结合了:

- **Trie (前缀树)** - 共享相同前缀的节点合并存储
- **Patricia (压缩)** - 单路径压缩，减少深度
- **Merkle (默克尔)** - 根哈希可验证完整性

```
MPT 核心特点:
├── 路径压缩 - 减少树深度
├── 节点共享 - 相同前缀复用
├── 默克尔根 - 状态一致性证明
└── 不可变性 - 每次修改生成新根
```

## 6.2 MPT 节点类型

```
                    MPT 节点类型

    ┌─────────────────────────────────────────────┐
    │                                              │
    │  1. 扩展节点 (Extension Node)                │
    │     ┌─────────────────────────────────┐     │
    │     │ [path, nextNode]                │     │
    │     │ 压缩共享路径                     │     │
    │     └─────────────────────────────────┘     │
    │                                              │
    │  2. 分支节点 (Branch Node)                   │
    │     ┌─────────────────────────────────┐     │
    │     │ [0..15 children, value]         │     │
    │     │ 16 个子指针 + 叶子值             │     │
    │     └─────────────────────────────────┘     │
    │                                              │
    │  3. 叶子节点 (Leaf Node)                     │
    │     ┌─────────────────────────────────┐     │
    │     │ [path, value]                   │     │
    │     │ path 以 0xe 或 0xf 开头          │     │
    │     └─────────────────────────────────┘     │
    │                                              │
    └─────────────────────────────────────────────┘
```

### 节点编码

```go
// trie/encoding.go

const (
    // 路径半字节编码
    // 0-15 表示实际的 nibble 值
    // 16 表示路径结束 (leaf)
    // 17 表示有偶数个 nibble 需要共享 (extension)
    pathTerminator byte = 16
    pathEven       byte = 17 // 偶数长度前缀
    pathOdd        byte = 18 // 奇数长度前缀
)

// 示例:
// key = [0x12, 0x34, 0x56]
// path = 0x21 0x43 0x65 0x80  (每个 nibble + pathOdd/Even)
```

### 节点示例

```
示例: 存储以下键值对

Key:    "dog"  → Value: "puppy"
Key:    "doe"  → Value: "reindeer"

MPT 结构:

                    [Extension: "d"]
                           │
                    ┌──────┴──────┐
                    ▼             ▼
                [Branch: "o"]   (空)
                    │
          ┌───────┴───────┐
          ▼               ▼
    [Extension: "g"]   [Extension: "e"]
          │               │
          ▼               ▼
    [Leaf: "dog"]   [Branch: ""]
    "puppy"          │
              ┌──────┴──────┐
              ▼             ▼
        [Leaf: ""]     [Leaf: "e"]
        "reindeer"       (空)
```

## 6.3 以太坊状态树

### 账户状态结构

```
以太坊账户:

{
    "nonce":    uint64,      // 交易序号
    "balance":  *big.Int,    // 账户余额
    "root":     common.Hash, // 存储树根 (contract storage)
    "codeHash": common.Hash  // 合约代码哈希
}

账户树结构:
┌─────────────────────────────────────────┐
│            World State Root             │
├─────────────────────────────────────────┤
│  │                                     │
│  ▼                                     │
│ [Branch Node]                          │
│  ├── 0: [Extension: "0x00..."] ───────►│ 账户地址以 0x00 开头
│  ├── 1: [Extension: "0x01..."] ───────►│
│  ├── 2: [Branch: ...]                  │
│  ...                                   │
│  └── f: [Extension: "0xff..."] ───────►│ 账户地址以 0xff 开头
└─────────────────────────────────────────┘
```

### 存储树结构

```
账户存储树 (Storage Trie):

                    [Storage Root]
                           │
                           ▼
                  [Branch/Extension/Leaf]
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
           slot 0      slot 1       slot N
           value       value        value
```

## 6.4 核心源码分析

### Trie 接口

```go
// trie/trie.go

type Trie interface {
    // 获取值
    Get(key []byte) ([]byte, error)

    // 设置值
    Put(key, value []byte) error

    // 删除值
    Delete(key []byte) error

    // 获取根哈希
    Hash() common.Hash

    // 提交到数据库
    Commit() (common.Hash, error)

    // 获取证明
    Prove(key []byte, fromLevel uint) ([][]byte, error)
}
```

### 节点结构

```go
// trie/node.go

type node interface {
    // 编码为 RLP
    EncodeRLP(w io.Writer) error

    // 缓存 ID
    cache() []byte
}

// 扩展节点
type shortNode struct {
    Key   []byte  // 压缩后的路径
    Val   node    // 指向子节点
    Flags nodeFlag
}

// 分支节点
type fullNode struct {
    Children [17]node  // 16 个 nibble + value
    Flags    nodeFlag
}

// 叶子节点 (shortNode 的特例)
type leafNode struct {
    // embedded in shortNode
}
```

### 哈希计算

```go
// trie/trie.go

func (t *Trie) Hash() common.Hash {
    // 如果为空，返回空根
    if t.root == nil {
        return emptyRoot
    }

    // 提交并返回根哈希
    hash, _ := t.commit(t.root)
    return hash
}

func (t *Trie) commit(n node) (common.Hash, error) {
    // 递归提交所有子节点
    // 计算节点的 RLP 哈希
    // 返回哈希值
}
```

## 6.5 数据库层

### key-value 存储

```
MPT 节点存储在 LevelDB 中:

┌─────────────────────────────────────────┐
│              LevelDB                     │
├─────────────────────────────────────────┤
│                                          │
│  Key: 0x48 + nodeHash                    │
│  Value: RLP-encoded node                 │
│                                          │
│  Key: 0x48 + blockHash                   │
│  Value: BlockStateTrie root              │
│                                          │
└─────────────────────────────────────────┘
```

```go
// ethdb/database.go

type Database interface {
    // 节点数据库
    OpenTrie(root common.Hash) (Trie, error)
    OpenStorageTrie(root common.Hash) (Trie, error)

    // 直接操作
    Put(key, value []byte) error
    Get(key []byte) ([]byte, error)
    Delete(key []byte) error

    // 批处理
    NewBatch() Batch
    Write(batch Batch) error
}
```

## 6.6 状态证明

### 默克尔证明

```go
// 验证状态证明

func VerifyProof(root common.Hash, key []byte, proof [][]byte) ([]byte, error) {
    // 1. 从证明构建部分 MPT
    trie := NewFromProof(proof)

    // 2. 获取值
    value, err := trie.Get(key)
    if err != nil {
        return nil, fmt.Errorf("proof invalid: %v", err)
    }

    // 3. 验证根哈希
    if trie.Hash() != root {
        return nil, fmt.Errorf("proof root mismatch")
    }

    return value, nil
}
```

### 轻节点证明

```
轻节点同步流程:

1. 客户端请求账户证明
   → GetProof(accountAddress)

2. 服务端返回证明
   ← AccountProof (MPT 节点列表)

3. 客户端验证
   → 重建部分 MPT
   → 验证根哈希
   → 提取账户状态
```

## 6.7 状态快照与裁剪

### 快照机制

```
                    状态快照流程
    ┌─────────────────────────────────────────┐
    │                                          │
    │  1. 生成快照                             │
    │     - 在某个高度拍照                     │
    │     - 记录所有账户                       │
    │                                          │
    │  2. 快照验证                             │
    │     - 下载快照根                         │
    │     - 对比默克尔根                       │
    │                                          │
    │  3. 快速同步                             │
    │     - 从快照恢复                         │
    │     - 继续同步新块                       │
    │                                          │
    └─────────────────────────────────────────┘
```

### 状态裁剪

```
状态裁剪策略:

├── 不活跃账户 - 超过 128 个块未访问
├── 旧状态     - 超过 128 个块的历史状态
└── 完整保留   - 当前状态和最近 127 个块

裁剪后保留:
├── 区块头 (所有)
├── 区块体 (最近 128 个)
└── 状态 (仅当前和快速同步需要的)
```

---

**下一步**: 继续阅读 [[07-EVM执行层]] 了解智能合约执行
