// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../../test/mocks/MockV3Aggreator.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address wethPriceFeed;
        address weth;
        address wbtcPriceFeed;
        address wbtc;
        uint256 deployerKey;
    }

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 1000e8;
    uint256 public constant DEFAULT_ANVIL_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaETHConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilETHConfig();
        }
    }

    function getSepoliaETHConfig() public view returns (NetworkConfig memory) {
        return
            NetworkConfig({
                wethPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
                weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
                wbtcPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
                wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
                deployerKey: vm.envUint("SEPOLIA_PRIVATE_KEY")
            });
    }

    function getOrCreateAnvilETHConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.wethPriceFeed != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();

        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(
            DECIMALS,
            ETH_USD_PRICE
        );
        ERC20Mock wETHMock = new ERC20Mock("wETH", "wETH", msg.sender, 1000e8);
        // ERC20Mock wETHMock = new ERC20Mock();

        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(
            DECIMALS,
            BTC_USD_PRICE
        );
        ERC20Mock wBTCMock = new ERC20Mock("wBTC", "wBTC", msg.sender, 1000e8);
        // ERC20Mock wBTCMock = new ERC20Mock();

        vm.stopBroadcast();

        return
            NetworkConfig({
                wethPriceFeed: address(ethUsdPriceFeed),
                weth: address(wETHMock),
                wbtcPriceFeed: address(btcUsdPriceFeed),
                wbtc: address(wBTCMock),
                deployerKey: DEFAULT_ANVIL_KEY
            });
    }
}
