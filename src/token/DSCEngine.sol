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
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    // ========== State Variables
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //Ngưỡng thanh lý, giá trị tài sản thế chấp phải lớn hơn 50usd so với giá trị của dsc được mint - 150% overcollateralized
    uint256 private constant LIQUITDATION_PRECISION = 100;
    uint256 private constant MIN_HELTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;

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
    event CollateralRedeemed(
        address indexed addressFrom,
        address indexed addressTo,
        address indexed token,
        uint256 amount
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
    function depositCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDSCToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(amountDSCToMint);
    }

    // Follow CEI Design Pattern
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][
            tokenCollateralAddress
        ] += amountCollateral;
        emit ColatteralDeposited(
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );
        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    // 1. Check giá trị của tài sản thế chấp phải lớn hơn số lượng DSC được mint ra.
    function mintDSC(
        uint256 amountDSCToMint
    ) public moreThanZero(amountDSCToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDSCToMint;
        _revertIfHelthFactorBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, amountDSCToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function redeemCollateralForDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDSCToBurn
    ) external {
        _burnDSC(amountDSCToBurn, msg.sender, msg.sender);
        _redeemCollateral(
            msg.sender,
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );
        _revertIfHelthFactorBroken(msg.sender);
    }

    // Muốn redeem lại tài sản đã thê chấp thì user cần phải:
    // 1 health factor phải cao hơn 1
    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public moreThanZero(amountCollateral) nonReentrant {
        _redeemCollateral(
            msg.sender,
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );
        _revertIfHelthFactorBroken(msg.sender);
    }

    function burnDSC(
        uint256 amountDSCToBurn
    ) public moreThanZero(amountDSCToBurn) {
        _burnDSC(amountDSCToBurn, msg.sender, msg.sender);
        _revertIfHelthFactorBroken(msg.sender);
    }

    // nếu giao thức bắt đầu gần đến mức dưới mức thế chấp, chúng ta cần ai đó thanh lý vị thế (gọi là liquidator)

    // $100 ETH backing $50 DSC (is fine)
    // $20 ETH backing $50 DSC (!!! warning, DSC không đáng 1$)

    // Nên khi gần đến ngưỡng thanh lí, ví dụ: $75 ETH backing $50 DSC
    // Liquidator sẽ lấy $75 ETH và đốt $50 DSC họ đang nắm giữ để giữ cho giao thức ổn định

    // Nếu user nào gần như là dưới mức thế chấp, giao thức sẽ cho phép các liquidator thanh lí tài sản của user đó

    /**
    @param collateral địa chỉ tài sản thế chấp để thanh lý
    @param user người dùng sẽ bị thanh lý nếu health factor dưới 1
    @param debtToCover số lượng DSC bạn liquidator muốn đốt để cải thiện chỉ số heath factor của người dùng
    @notice liquidator có thể thanh lý một phần tài sản của user
    @notice liquidator sẽ nhận được 10% LIQUIDATION_BONUS khi nhận lấy tài sản thế chấp của người dùng
    @notice Nếu mức thế chấp của giao thức chỉ là 100% thì giao thức sẽ không thể thanh lý được ai cả. Ví dụ là nếu giá của tài sản thế chấp giảm mạnh trước khi bất kỳ ai bị thanh lý.
    @notice Giao thức sẽ được thế chấp ở mức 150% để chức năng này hoạt động
     */
    function liquidate(
        address collateral,
        address user,
        uint256 debtToCover
    ) external moreThanZero(debtToCover) nonReentrant {
        // Check health factor của người dùng
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HELTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }

        // Đốt số nợ DSC của user
        // Lấy collateral của user đó
        // Bad user: $140 ETH => $100 DSC
        // debtToCover = $100
        // $100 DSC == ??? ETH - tìm xem với $100 DSC hiện tại thì đổi ra được bao nhiêu ETH
        // 0.05 ETH
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUSD(
            collateral,
            debtToCover
        );
        // Trả cho liquidator 10% bonus. Ví dụ: liquidator sẽ nhận được $110 wETH (từ người dùng bị thanh lý) khi họ đốt $100 DSC
        // Triển khai tính năng thanh lý trước khi giao thức bị vỡ nợ
        // Lấy thêm một số lượng vào trong treasury
        uint256 bonusCollateral = (tokenAmountFromDebtCovered *
            LIQUIDATION_BONUS) / LIQUITDATION_PRECISION;

        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered +
            bonusCollateral;

        _redeemCollateral(
            user,
            msg.sender,
            collateral,
            totalCollateralToRedeem
        );

        // Burn DSC khi rút tài sản thế chấp thành công
        _burnDSC(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHelthFactorBroken(msg.sender);
    }

    // ========== Private & Internal View Functions

    /**
    @dev low-level internal function, không gọi function này trừ khi đã check health factor của address user burn dsc
     */
    function _burnDSC(
        uint256 amountDSCToBurn,
        address onBehalfOf,
        address toFrom
    ) private {
        s_DSCMinted[onBehalfOf] -= amountDSCToBurn;
        bool success = i_dsc.transferFrom(
            toFrom,
            address(this),
            amountDSCToBurn
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDSCToBurn);
    }

    function _redeemCollateral(
        address from,
        address to,
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) private {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(
            from,
            to,
            tokenCollateralAddress,
            amountCollateral
        );
        bool success = IERC20(tokenCollateralAddress).transfer(
            to,
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

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
        return _calculateHealthFactor(totalDSCMinted, collateralValueInUSD);
    }

    function _calculateHealthFactor(
        uint256 totalDSCMinted,
        uint256 collateralValueInUSD
    ) internal pure returns (uint256) {
        if (totalDSCMinted == 0) return type(uint256).max;

        uint256 collateralAdjustedForThreshold = (collateralValueInUSD *
            LIQUIDATION_THRESHOLD) / 100;
        return (collateralAdjustedForThreshold * 1e18) / totalDSCMinted;
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
    function getTokenAmountFromUSD(
        address token,
        uint256 usdAmountInWei
    ) public view returns (uint256) {
        // tìm ra giá trị của token
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int price, , , ) = priceFeed.latestRoundData();

        // ($10e18 * 1e18) / (2000e8 *1e10) - Ví dụ: 10DSC / 2000 (giá ví dụ của ETH)
        return ((usdAmountInWei * PRECISION) /
            (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

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

    function getAccountInformation(
        address user
    )
        external
        view
        returns (uint256 totalDSCMinted, uint256 collateralValueInUSD)
    {
        return _getAccountInformation(user);
    }

    function getCollateralAmountOfAUser(
        address user,
        address token
    ) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    // function getDSCMintedAmountOfAUser(
    //     address user
    // ) external view returns (uint256) {
    //     return s_DSCMinted[user];
    // }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }
}
