// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {DSCEngineInterface} from "../interfaces/DSCEngineInterface.sol";
import {DecentralizedStableCoinERC20} from "../token/DecentralizedStableCoinERC20.sol";

/**
 @title DSC Engine
 @dev Hệ thống được thiết kế tối giản nhất có thể, token luôn được duy trì dựa trên giá peg 1 DSC = $1 USD
 @dev Thuộc tính của stablecoin:
 - Tài sản thế chấp ngoại sinh (BTC, ETH)
 - Cố định bằng giá USD Dollar
 - Ổn định bằng thuật toán

 @notice token này giống DAI nhưng không có DAO Governance và không có fees, nó chỉ được backed bằng WETH và WBTC
 @notice contract này là core của DSC System. Chứa mọi logic xử lý minting, redeeming, nạp và rút tài sản thế chấp.
 @notice contract này một chút dựa trên MakerDAO DSS (DAI) system.
*/
contract DSCEngine is DSCEngineInterface {
    // ========== Errors
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();

    // ========== State Variables
    mapping(address token => address priceFeed) private s_priceFeed; // token to priceFeed

    DecentralizedStableCoinERC20 private immutable i_dsc;

    // ========== Modifiers
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    // modifier isAllowedToken (address token){

    // }

    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address dscAddress
    ) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }

        // USD Price Feed. Example: BTC / USD or ETH / USD
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeed[tokenAddresses[i]] = priceFeedAddresses[i];
        }

        i_dsc = DecentralizedStableCoinERC20(dscAddress);
    }

    // ========== Functions

    // ========== External Functions
    function depositCollateralAndMintDSC() external {}

    function depositCollateral(
        address tokenCollateralContract,
        uint256 amount
    ) external moreThanZero(amount) {}

    function redeemCollateralForDSC() external {}

    function redeemCollateral() external {}

    function burnDSC() external {}

    function liquidate() external view {}

    function getHealthFactor() external {}
}
