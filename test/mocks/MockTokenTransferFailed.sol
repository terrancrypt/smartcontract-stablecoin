// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ERC20, ERC20Burnable} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract MockTokenTransferFailed is ERC20Burnable, Ownable {
    error DecentralizedStableCoin__MustBeMoreThanZero();
    error DecentralizedStableCoin__BurnAmountExeedsBalance();
    error DecentralizedStableCoin__NotZeroAddress();

    constructor() ERC20("Decentralized Stable Coin", "DSC") {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);

        if (_amount <= 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }

        if (balance < _amount) {
            revert DecentralizedStableCoin__BurnAmountExeedsBalance();
        }

        super.burn(_amount);
    }

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

    function transfer(
        address,
        /*recipient*/ uint256 /*amount*/
    ) public pure override returns (bool) {
        return false;
    }
}
