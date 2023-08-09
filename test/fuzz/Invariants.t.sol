// SPDX-License-Identifier: MIT

// Chứa các invariant testa khi gọi hàm (aka properties)

// Cái gì của protocols là bất biến?
// 1. Tổng lượng lưu hành của DSC StableCoin luôn luôn thấp hơn tổng tài sản thế chấp trong giao thức
// 2. Getter view function sẽ không bao giờ nên bị revert => evergreen invariant

pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/token/DSCEngine.sol";
import {DecentralizedStableCoinERC20} from "../../src/token/DecentralizedStableCoinERC20.sol";
import {HelperConfig} from "../../script/helpers/HelperConfig.s.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantsTest is StdInvariant, Test {
    DSCEngine dscEngine;
    DecentralizedStableCoinERC20 dsc;
    HelperConfig config;
    Handler handler;

    address wethPriceFeed;
    address weth;
    address wbtcPriceFeed;
    address wbtc;
    uint256 deployerKey;

    function setUp() external {
        DeployDSC deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();
        (wethPriceFeed, weth, wbtcPriceFeed, wbtc, ) = config
            .activeNetworkConfig();
        // targetContract(address(dscEngine));
        handler = new Handler(dsc, dscEngine);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThatTotalSupplyDollars()
        public
        view
    {
        // Lấy tổng giá trị của tài sản thế chấp có trong giao thức
        // so sánh với tổng nợ (DSC được mint)

        uint256 totalSupply = dsc.totalSupply();
        uint256 totalwETHDeposited = IERC20(weth).balanceOf(address(dscEngine));
        uint256 totalwBTCDeposited = IERC20(wbtc).balanceOf(address(dscEngine));

        uint256 wETHValue = dscEngine.getUSDValueOfCollateral(
            weth,
            totalwETHDeposited
        );
        uint256 wBTCValue = dscEngine.getUSDValueOfCollateral(
            wbtc,
            totalwBTCDeposited
        );

        assert(wETHValue + wBTCValue >= totalSupply);
    }

    // function invariant_gettersShouldNotRevert() public {
    //     dscEngine.getAccountCollateralValueInUSD(user);
    //     dscEngine.getAccountInformation(user);
    //     dscEngine.getCollateralAmountOfAUser(user, token);
    //     dscEngine.getHealthFactor(user);
    //     dscEngine.getTokenAmountFromUSD(token, usdAmountInWei);
    //     dscEngine.getUSDValueOfCollateral(token, amount);
    // }
}
