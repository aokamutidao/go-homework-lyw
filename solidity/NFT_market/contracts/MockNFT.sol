// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title MockNFT
 * @dev 简单的 ERC721 NFT 合约，支持铸造功能
 */
contract MockNFT is ERC721, ERC721URIStorage, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdCounter;

    // NFT 创建者记录
    mapping(uint256 => address) private _creators;

    // 批量铸造的 nonce
    uint256 public nextTokenIdToMint;

    constructor() ERC721("MockNFT", "MNFT") Ownable(msg.sender) {}

    /**
     * @dev 铸造 NFT 到指定地址
     */
    function safeMint(address to, string memory uri) external onlyOwner {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
        _creators[tokenId] = msg.sender;
    }

    /**
     * @dev 批量铸造 NFT
     */
    function batchMint(address to, string[] memory uris) external onlyOwner {
        for (uint256 i = 0; i < uris.length; i++) {
            uint256 tokenId = _tokenIdCounter.current();
            _tokenIdCounter.increment();
            _safeMint(to, tokenId);
            _setTokenURI(tokenId, uris[i]);
            _creators[tokenId] = msg.sender;
        }
    }

    /**
     * @dev 获取 NFT 创建者
     */
    function creatorOf(uint256 tokenId) external view returns (address) {
        return _creators[tokenId];
    }

    /**
     * @dev 获取当前 NFT 总量
     */
    function getTotalSupply() external view returns (uint256) {
        return _tokenIdCounter.current();
    }

    // 重写 burn 函数
    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    // 重写 tokenURI 函数
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    // 支持接口
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
