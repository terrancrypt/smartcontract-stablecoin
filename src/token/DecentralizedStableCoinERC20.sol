// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ERC20, ERC20Burnable} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title DecentrilizedStableCoin
 * @author terrancrypt
 * @notice Collateral: Exogeenouse (BTC & ETH)
 * @notice Minting: Argorithmic
 * @notice Relative Stability: Pegged to USD
 * @notice đây là contract được governed bởi DSCEngine. Contract này triển khai ERC20 trong hệ thống stablecoin
 * ERC20 với minting và burning logic
 */
contract DecentralizedStableCoinERC20 is ERC20Burnable, Ownable {
    error DecentralizedStableCoin__MustBeMoreThanZero();
    error DecentralizedStableCoin__BurnAmountExeedsBalance();
    error DecentralizedStableCoin__NotZeroAddress();

    constructor() ERC20("DecentralizedStableCoin", "DSC") {}

    /**
     * @notice hàm burn có ghi đè chức năng của hàm chính nên phải gọi hàm super để chạy lại hàm burn gốc
     */
    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);

        if (_amount <= 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }

        if (balance < _amount) {
            revert DecentralizedStableCoin__BurnAmountExeedsBalance();
        }

        super.burn(_amount); // super dùng để sử dụng function burn của class cha, ở đây là ERC20Burnable
    }

    /**
     * @notice hàm mint không thực sự ghi đè chức năng gì của function gốc nên không cần override và gọi hàm super
     */
    function mint(
        address _to,
        uint256 _amount
    ) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStableCoin__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }

        _mint(_to, _amount);
        return true;
    }
}
