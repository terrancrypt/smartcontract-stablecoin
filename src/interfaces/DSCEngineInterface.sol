// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/**
 * @title The interfaces for DSC Engine contract
 */

interface DSCEngineInterface {
    /**
     * @notice thế chấp tài sản và mint DSC
     */
    function depositCollateralAndMintDSC() external;

    /**
     * @param tokenCollateralContract địa chỉ của token nạp vào như một tài sản thế chấp
     * @param amount số lượng token
     */
    function depositCollateral(
        address tokenCollateralContract,
        uint256 amount
    ) external;

    /**
     * @notice mintDSC
     * @param amountToMint số lượng token DSC muốn mint
     * @notice giá trị của tài sản thế chấp phải ở ngưỡng tối thiểu cho phép. Ví dụ: $200 ETH => $20 DSC
     */
    function mintDSC(uint256 amountToMint) external;

    /**
     * @notice trả lại DSC đã mint và chuộc lại tài sản thể chấp
     */
    function redeemCollateralForDSC() external;

    function redeemCollateral() external;

    /**
     * @notice đốt DSC khi user trả lại tài sản thế chấp
     */
    function burnDSC() external;

    /**
     * @notice thanh lý tài sản
     */
    function liquidate() external view;

    /**
     * @notice getHealthFactor
     */
    function getHealthFactor() external;

    /**
     * @notice Returns the total collateral value in USD for a user
     */
    function getAccountCollateralValueInUSD(
        address user
    ) external view returns (uint256);

    /**
     * @notice Returns the USD value of the specified collateral amount
     * @param token The address of the collateral token
     * @param amount The amount of collateral tokens
     */
    function getUSDValueOfCollateral(
        address token,
        uint256 amount
    ) external view returns (uint256);
}
