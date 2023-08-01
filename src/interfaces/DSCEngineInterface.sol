// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/**
@title The interfaces for DSC Engine contract
*/

interface DSCEngineInterface {
    /** @notice thế chấp tài sản và mint DSC*/
    function depositCollateralAndMintDSC() external;

    /**
    @param tokenCollateralContract địa chỉ của token nạp vào như một tài sản thế chấp
    @param amount số lượng token
     */
    function depositCollateral(
        address tokenCollateralContract,
        uint256 amount
    ) external;

    /** @notice trả lại DSC đã mint và chuộc lại tài sản thể chấp */
    function redeemCollateralForDSC() external;

    function redeemCollateral() external;

    /** @notice đốt DSC khi user trả lại tài sản thế chấp */
    function burnDSC() external;

    /** @notice thanh lý tài sản */
    function liquidate() external view;

    /** @notice getHealthFactor */
    function getHealthFactor() external;
}
