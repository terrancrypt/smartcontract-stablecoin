// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {DSCEngineInterface} from "../interfaces/DSCEngineInterface.sol";
import {DecentralizedStableCoinERC20} from "../token/DecentralizedStableCoinERC20.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {AggregatorV3Interface} from "lib/chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title DSC Engine
 *  @dev Hệ thống được thiết kế tối giản nhất có thể, token luôn được duy trì dựa trên giá peg 1 DSC = $1 USD
 *  @dev Thuộc tính của stablecoin:
 *  - Tài sản thế chấp ngoại sinh (BTC, ETH)
 *  - Cố định bằng giá USD Dollar
 *  - Ổn định bằng thuật toán
 *
 *  @notice token này giống DAI nhưng không có DAO Governance và không có fees, nó chỉ được backed bằng WETH và WBTC
 *  @notice contract này là core của DSC System. Chứa mọi logic xử lý minting, redeeming, nạp và rút tài sản thế chấp.
 *  @notice contract này một chút dựa trên MakerDAO DSS (DAI) system.
 */
contract DSCEngine is DSCEngineInterface, ReentrancyGuard {
    // ========== Errors
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreakHealthFactor(uint256 healtFactor);
    error DSCEngine__MintFailed();

    // ========== State Variables
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUITDATION_THRESHOLD = 50; //Ngưỡng thanh lý, giá trị tài sản thế chấp phải lớn hơn 50usd so với giá trị của dsc được mint - 150% overcollateralized
    uint256 private constant LIQUITDATION_PRECISION = 100;
    uint256 private constant MIN_HELTH_FACTOR = 1;

    mapping(address token => address priceFeed) private s_priceFeeds; // token to priceFeed
    mapping(address user => mapping(address token => uint256 amount))
        private s_collateralDeposited; // ánh xạ địa chỉ ví của người dùng tới token mà họ nắm giữ và số lượng token đó là bao nhiêu. Ví dụ: 0x222321dkas2... => (0x233dsasdas... => 23 ETH);
    mapping(address user => uint256 amountDSCMinted) private s_DSCMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoinERC20 private immutable i_dsc;

    // ========== Events
    event ColatteralDeposited(
        address indexed user,
        address indexed token,
        uint256 indexed amount
    );

    // ========== Modifiers
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

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
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_dsc = DecentralizedStableCoinERC20(dscAddress);
    }

    // ========== Functions

    // ========== External Functions
    function depositCollateralAndMintDSC() external {}

    // Follow CEI Design Pattern
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amount
    )
        external
        moreThanZero(amount)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amount;
        emit ColatteralDeposited(msg.sender, tokenCollateralAddress, amount);
        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            amount
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    // 1. Check giá trị của tài sản thế chấp phải lớn hơn số lượng DSC được mint ra.
    function mintDSC(
        uint256 amountToMint
    ) external moreThanZero(amountToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountToMint;
        _revertIfHelthFactorBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, amountToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function redeemCollateralForDSC() external {}

    function redeemCollateral() external {}

    function burnDSC() external {}

    function liquidate() external view {}

    function getHealthFactor() external {}

    // ========== Private & Internal View Functions
    function _getAccountInformation(
        address user
    )
        private
        view
        returns (uint256 totalDSCMinted, uint256 collateralValueInUSD)
    {
        totalDSCMinted = s_DSCMinted[user];
        collateralValueInUSD = getAccountCollateralValueInUSD(user);
    }

    /**
    Returns tình trạng có thể bị thanh lý hay không của một người dùng
    Nếu chỉ số health factor của người dùng xuống dưới 1 thì người dùng có thể bị thanh lý tài sản đã thế chấp
    Một phần dựa vào: https://docs.aave.com/risk/asset-risk/risk-parameters
     */
    function _healthFactor(address user) private view returns (uint256) {
        // Cần 2 thứ: 1 là số dsc của người dùng đã mint (tổng giá trị), 2 là tổng giá trị tài sản của họ đã thế chấp (giá trị của Eth hoặc btc so với usd)
        (
            uint256 totalDSCMinted,
            uint256 collateralValueInUSD
        ) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUSD /
            LIQUITDATION_THRESHOLD) / LIQUITDATION_PRECISION;
        return ((collateralAdjustedForThreshold * PRECISION) / totalDSCMinted);
    }

    // 1. Check health factor (kiểm tra xem người dùng có đủ tài sản thế chấp hay không?)
    // 2. Revert nếu người dùng không đủ tài sản thế chấp họ mong muốn
    function _revertIfHelthFactorBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);

        if (userHealthFactor < MIN_HELTH_FACTOR) {
            revert DSCEngine__BreakHealthFactor(userHealthFactor);
        }
    }

    // ========== Public & External View Functions
    function getAccountCollateralValueInUSD(
        address user
    ) public view returns (uint256 totalCollateralInUsd) {
        // loop qua từng loại tài sản của người dùng đã thế chấp và tìm tổng giá trị của loại tài sản đó
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralInUsd += getUSDValueOfCollateral(token, amount);
        }
        return totalCollateralInUsd;
    }

    function getUSDValueOfCollateral(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int price, , , ) = priceFeed.latestRoundData();
        return
            ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }
}
