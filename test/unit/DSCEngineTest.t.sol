// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoinERC20} from "../../src/token/DecentralizedStableCoinERC20.sol";
import {DSCEngine} from "../../src/token/DSCEngine.sol";
import {HelperConfig} from "../../script/helpers/HelperConfig.s.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";

import {MockV3Aggregator} from "../../test/mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoinERC20 dsc;
    DSCEngine dscEngine;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");
    uint256 public AMOUNT_COLLATERAL = 10 ether;
    uint256 public AMOUNT_COLLATERAL_TO_COVER = 20 ether;
    uint256 public AMOUNT_DSC_TO_MINT = 100 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();
        (ethUsdPriceFeed, weth, btcUsdPriceFeed, wbtc, ) = config
            .activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    // ========== Constructor Tests
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(
            DSCEngine
                .DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength
                .selector
        );

        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    // ========== Price Tests
    function testGetUSDValue() public {
        uint256 ethAmount = 15e18; // 15 ETH
        // 15e18 * 2000/ETH = 30,000e18;
        uint256 expectedUSD = 30000e18;
        uint256 actualUSD = dscEngine.getUSDValueOfCollateral(weth, ethAmount);
        assertEq(expectedUSD, actualUSD);
    }

    function testGetTokenAmountFromUSD() public {
        uint256 usdAmount = 100 ether;
        // $2000 / ETH, $100 = 0.05
        uint256 expectedWETH = 0.05 ether;
        uint256 actualWETH = dscEngine.getTokenAmountFromUSD(weth, usdAmount);
        assertEq(expectedWETH, actualWETH);
    }

    // ========== Deposit Collateral And Mint DSC Tests
    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier depositedCollateralAndMintDSC() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDSC(
            weth,
            AMOUNT_COLLATERAL,
            AMOUNT_DSC_TO_MINT
        );
        vm.stopPrank();
        _;
    }

    function testUserCanDepositAndMintDSC()
        public
        depositedCollateralAndMintDSC
    {
        vm.prank(USER);
        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = dscEngine
            .getAccountInformation(USER);
        uint256 expectedDepositAmount = dscEngine.getTokenAmountFromUSD(
            weth,
            collateralValueInUSD
        );
        assertEq(totalDSCMinted, AMOUNT_DSC_TO_MINT);
        assertEq(expectedDepositAmount, AMOUNT_COLLATERAL);
    }

    // ========== Deposit Collateral Tests

    function testRevertIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(USER, AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.depositCollateral(address(weth), 0);
        vm.stopPrank();
    }

    function testRevertWithUnapprovedCollateral() public {
        ERC20Mock randomToken = new ERC20Mock("RAN", "RAN", USER, 100e18);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dscEngine.depositCollateral(address(randomToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCanDepositCollateralAndGetAccountInfo()
        public
        depositedCollateral
    {
        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = dscEngine
            .getAccountInformation(USER);

        uint256 expectedDSCMinted = 0;

        // 10 ether * $2000/ETH = $20,000;
        uint256 expectedDepositAmount = dscEngine.getTokenAmountFromUSD(
            weth,
            collateralValueInUSD
        );

        assertEq(totalDSCMinted, expectedDSCMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    // ========== mintDSC Tests
    function testRevertIfMintDSCAmountIsZero() public {
        vm.prank(USER);
        uint256 amountDSCToMint = 0;
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.mintDSC(amountDSCToMint);
    }

    function testUserCanMintDSC() public depositedCollateral {
        vm.prank(USER);
        dscEngine.mintDSC(AMOUNT_DSC_TO_MINT);
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, AMOUNT_DSC_TO_MINT);
    }

    // ========== redeemCollateralForDSC Tests
    function testUserCanRedeemCollateralForDSC()
        public
        depositedCollateralAndMintDSC
    {
        vm.startPrank(USER);
        dsc.approve(address(dscEngine), AMOUNT_DSC_TO_MINT);
        dscEngine.redeemCollateralForDSC(
            weth,
            AMOUNT_COLLATERAL,
            AMOUNT_DSC_TO_MINT
        );
        vm.stopPrank();

        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = dscEngine
            .getAccountInformation(USER);
        assertEq(totalDSCMinted, 0);
        assertEq(collateralValueInUSD, 0);
    }

    // ========== redeemCollateral Tests
    function testUserCanRedeemCollateral() public depositedCollateral {
        vm.prank(USER);
        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        uint256 userBalance = ERC20Mock(weth).balanceOf(USER);
        assertEq(userBalance, AMOUNT_COLLATERAL);
    }

    // ========== burnDSC Tests
    // function testRevertIfBurnAmountIsZero () public {
    //     vm.startPrank(USER);
    //     vm.expectRevert();
    // }

    function testUserCanBurnDSC() public depositedCollateralAndMintDSC {
        vm.startPrank(USER);
        dsc.approve(address(dscEngine), AMOUNT_DSC_TO_MINT);
        dscEngine.burnDSC(AMOUNT_DSC_TO_MINT);
        vm.stopPrank();

        uint256 expectedDSCAmountOfUser = dsc.balanceOf(USER);
        assertEq(expectedDSCAmountOfUser, 0);
    }

    // ========== liquidate Tests
    modifier liquidated() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDSC(
            weth,
            AMOUNT_COLLATERAL,
            AMOUNT_DSC_TO_MINT
        );
        vm.stopPrank();

        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        ERC20Mock(weth).mint(LIQUIDATOR, AMOUNT_COLLATERAL_TO_COVER);

        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL_TO_COVER);
        dscEngine.depositCollateralAndMintDSC(
            weth,
            AMOUNT_COLLATERAL_TO_COVER,
            AMOUNT_DSC_TO_MINT
        );
        dsc.approve(address(dscEngine), AMOUNT_DSC_TO_MINT);
        dscEngine.liquidate(weth, USER, AMOUNT_DSC_TO_MINT); // Liquidator cover whole user's debt
        vm.stopPrank();
        _;
    }

    function testCantLiquidateAUserWithGoodHealthFactor()
        public
        depositedCollateralAndMintDSC
    {
        ERC20Mock(weth).mint(LIQUIDATOR, AMOUNT_COLLATERAL);

        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDSC(
            weth,
            AMOUNT_COLLATERAL,
            AMOUNT_DSC_TO_MINT
        );
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dscEngine.liquidate(weth, USER, AMOUNT_DSC_TO_MINT);
        vm.stopPrank();
    }

    function testLiquidatorTakesUserDebt() public liquidated {
        (uint256 liquidatorDSCMinted, ) = dscEngine.getAccountInformation(
            LIQUIDATOR
        );
        assertEq(liquidatorDSCMinted, AMOUNT_DSC_TO_MINT);
    }

    function testUserHasNoMoreDebt() public liquidated {
        (uint256 userDSCMinted, ) = dscEngine.getAccountInformation(USER);
        assertEq(userDSCMinted, 0);
    }

    // ========== healthFactor Tests
    // function testUserHealthFactor() public depositedCollateral {}

    // ========== View & Pure Functions Test
    function testGetAccountCollateralValueInUSD()
        public
        depositedCollateralAndMintDSC
    {
        uint256 usdValueOfAmountCollateral = dscEngine.getUSDValueOfCollateral(
            weth,
            AMOUNT_COLLATERAL
        );

        vm.prank(USER);
        uint256 expectedAccountCollateralValueInUSD = dscEngine
            .getAccountCollateralValueInUSD(USER);

        assertEq(
            usdValueOfAmountCollateral,
            expectedAccountCollateralValueInUSD
        );
    }

    function testGetCollateralAmountOfAUser() public depositedCollateral {
        uint256 expectedAmountCollateral = dscEngine.getCollateralAmountOfAUser(
            USER,
            weth
        );
        assertEq(AMOUNT_COLLATERAL, expectedAmountCollateral);
    }

    function testGetUserHealthFactor() public depositedCollateralAndMintDSC {
        vm.prank(USER);
        uint256 userHealthFactor = dscEngine.getHealthFactor(USER);
        console.log(userHealthFactor);
    }
}
