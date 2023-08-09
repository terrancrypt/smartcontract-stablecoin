// SPDX-License-Identifier: MIT

// Handler sẽ thu hẹp khoảng cách khi gọi hàm (hạn chế các gọi hàm lãng phí / wasted run lặp đi lặp lại)

pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/token/DSCEngine.sol";
import {DecentralizedStableCoinERC20} from "../../src/token/DecentralizedStableCoinERC20.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DecentralizedStableCoinERC20 dsc;
    DSCEngine dscEngine;

    ERC20Mock weth;
    ERC20Mock wbtc;

    address[] public usersWithCollateralDeposited;
    MockV3Aggregator ethUSDPriceFeed;
    MockV3Aggregator btcUSDPriceFeed;

    uint256 public constant MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DecentralizedStableCoinERC20 _dsc, DSCEngine _dscEngine) {
        dsc = _dsc;
        dscEngine = _dscEngine;

        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUSDPriceFeed = MockV3Aggregator(
            dscEngine.getCollateralTokenPriceFeed(address(weth))
        );
    }

    function mintDSC(uint256 amount, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[
            addressSeed % usersWithCollateralDeposited.length
        ];
        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = dscEngine
            .getAccountInformation(sender);
        int256 maxDSCToMint = (int256(collateralValueInUSD) / 2) -
            int256(totalDSCMinted);
        if (maxDSCToMint < 0) {
            return;
        }
        amount = bound(amount, 0, uint256(maxDSCToMint));
        if (amount == 0) {
            return;
        }

        vm.startPrank(sender);
        dscEngine.mintDSC(amount);
        vm.stopPrank();
    }

    function depositCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        usersWithCollateralDeposited.push(msg.sender);
    }

    // redeemCollateral => Call function này khi có collateral để redeem
    function redeemCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = dscEngine.getCollateralAmountOfAUser(
            msg.sender,
            address(collateral)
        );
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);

        if (amountCollateral == 0) {
            return;
        }
        dscEngine.redeemCollateral(address(collateral), amountCollateral);
    }

    // Function này sẽ phá vỡ invariant test
    // function UpdateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(int256(newPrice));
    //     ethUSDPriceFeed.updateAnswer(newPriceInt);
    // }

    // ========== Helper Functions
    function _getCollateralFromSeed(
        uint256 collateralSeed
    ) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}
