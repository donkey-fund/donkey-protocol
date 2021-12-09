// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.5.6;
pragma experimental ABIEncoderV2;

import "../lending/Controller.sol";

contract StakingStorage {
    bool internal _notEntered;

    address donkeyAddress;

    address public admin;

    Controller controller;

    struct StakingMetaData {
        // no-scale
        uint lockupTerm;
        // 1e18 scale 
        uint totalInterestLimitAmount;
        // 1e18 scale 
        // ex) 30% : 0.3 * 1e18
        uint interestRate;
        // 1e18 scale 
        uint totalPrincipalAmount;
        // 1e18 scale
        uint totalPaidInterestAmount;
    }

    StakingMetaData public stakingMetaData;

    struct StakingProduct {
        uint releaseTime;
        uint principal;
    }

    struct StakingProductView {
        uint startTime;
        uint releaseTime;
        uint principal;
        uint lockupTerm;
        uint interestRate;
    }

    mapping(address => uint[]) public allStakingProductsTimestampOf;
    mapping(address => mapping(uint => StakingProduct)) public stakingProductOf;
}

contract StakingInterface is StakingStorage {

    event Mint(address minter, uint mintAmount);
    event Redeem(address redeemer, uint redeemAmount);
    event RedeemPrincipal(address redeemer, uint redeemAmount);
    event UpdateStakingStandard(uint newLockupTerm, uint newLimitAmount, uint newInterestRate);
    event UpdateController(Controller oldController, Controller newController);
    event UpdateAdmin(address oldAdmin, address newAdmin);

    function mint(uint mintAmount) external returns (uint);

    function redeem(uint registeredTimestamp) external returns (uint);

    function redeemPrincipal(uint registeredTimestamp) external returns (uint); 

    function currentUsedRateOfInterestLimit() external view returns (uint);

    function updateStakingStandard(uint newLockupTerm, uint newLimitAmount, uint newInterestRate) external;

    function stakingProductsOf(address account) external view returns (StakingProductView[] memory);

    function currentTotalDonBalanceOf(address account) public view returns (uint);
}
