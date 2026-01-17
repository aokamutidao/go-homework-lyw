// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockERC20
 * @dev 用于测试的 ERC20 代币合约，支持铸造功能
 */
contract MockERC20 is ERC20, Ownable {
    uint8 private _decimals;

    constructor(
        string memory name,
        string memory symbol,
        uint8 dec
    ) ERC20(name, symbol) Ownable(msg.sender) {
        _decimals = dec;
    }

    function decimals() public view override returns uint8) {
        return _decimals;
    }

    /**
     * @dev 铸造代币到指定地址（仅所有者）
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @dev 燃烧代币
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}
