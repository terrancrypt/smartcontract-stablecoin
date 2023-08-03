// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoinERC20} from "../src/token/DecentralizedStableCoinERC20.sol";
import {DSCEngine} from "../src/token/DSCEngine.sol";
import {HelperConfig} from "./helpers/HelperConfig.s.sol";

contract DeployDSC is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (DecentralizedStableCoinERC20, DSCEngine) {
        HelperConfig config = new HelperConfig();
        (
            address wethPriceFeed,
            address weth,
            address wbtcPriceFeed,
            address wbtc,
            uint256 deployerKey
        ) = config.activeNetworkConfig();

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethPriceFeed, wbtcPriceFeed];

        vm.startBroadcast();
        DecentralizedStableCoinERC20 dsc = new DecentralizedStableCoinERC20();
        DSCEngine dscEngine = new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(dsc)
        );
        dsc.transferOwnership(address(dscEngine));
        vm.stopBroadcast();
        return (dsc, dscEngine);
    }
}
