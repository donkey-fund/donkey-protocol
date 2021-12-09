// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.5.6;

// Original work from Compound: https://github.com/compound-finance/compound-protocol/blob/master/contracts/ComptrollerStorage.sol

import "./DToken.sol";

import "../oracle/PriceOracle.sol";

contract ControllerStorage {
    struct Market {
        bool isListed;
        uint collateralFactorMantissa;
        mapping(address => bool) accountMembership;
        bool isDonkeyed;
    }

    PriceOracle priceOracle;

    address public admin;

    address[] borrowers;

    mapping(address => bool) public protectedAssets;
    mapping(address => DToken[]) public accountAssets;

    mapping(address => Market) public markets;

    address public DONKEY_ADDRESS;

    // Guardians
    mapping(address => bool) public isPauseGuardian;
    mapping(address => bool) public isMintPaused;
    mapping(address => bool) public isBorrowPaused;

    // oracle guardian
    mapping(address => bool) public oracleGuardianPaused;

    bool public transferGuardianPaused;
    // currently unused. replaced with 'isSeizePaused'.
    bool public seizeGuardianPaused;

    mapping(address => uint) liquidationIncentiveMantissa;

    mapping(address => uint) public borrowCaps;

    uint public closeFactorMantissa;

    // Donkey Token  $_$
    uint public donkeyLockUpBlock;
    struct DonkeyMarketState {
        uint224 index;
        uint32 block;
    }
    
    DToken[] public allMarkets;

    uint public donkeyRate;

    mapping(address => uint) public donkeySpeeds;

    mapping(address => DonkeyMarketState) public donkeySupplyState;

    mapping(address => DonkeyMarketState) public donkeyBorrowState;

    mapping(address => mapping(address => uint)) public donkeySupplierIndex;

    mapping(address => mapping(address => uint)) public donkeyBorrowerIndex;

    mapping(address => uint) public donkeyAccrued;

    mapping(address => bool) public isSeizePaused;

    mapping(address => bool) public isStakingContract;
}
