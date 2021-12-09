// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.5.6;
pragma experimental ABIEncoderV2;

contract VDONStakingStorage {
    bool internal _notEntered;

    address public admin;

    address DONAddress;

    address ecoCNGAddress;

    address VDONAddress;

    struct TokenMetaData {
        // 1e18 scale
        uint interestLimitAmount;
        uint interestRate;
        uint paidInterestAmount;
    }
    
    struct ProductInfo {
        bool isActivate;
        // no-scale
        uint lockupTerm;
        // ex ) 1, 4
        uint VDONExchangeRate;
        // 1e18 scale 
        TokenMetaData DONInfo;
        TokenMetaData ecoCNGInfo;

        uint totalPrincipalAmount;
    }

    mapping(uint => ProductInfo) public getProductInfoById;
    uint public freshProductInfoId;

    struct EnteredProduct {
        uint productInfoId;
        uint releaseTime;
        uint principal;
    }

    struct ProductInfoView {
        bool isActivate;
        uint lockupTerm;
        uint VDONExchangeRate;
        TokenMetaData DONInfo;
        TokenMetaData ecoCNGInfo;
        uint totalPrincipalAmount;
        uint productInfoId;
        uint currentUsedRateOfInterest;
    }

    struct ProductView {
        uint startTime;
        uint releaseTime;
        uint principal;
        uint lockupTerm;
        uint interestRateOfDON;
        uint interestRateofEcoCNG;
        uint vDONExchangeRate;
        uint productInfoId;
        uint productId;
    }

    uint public freshProductId;

    // account => productId[]
    mapping(address => uint[]) public allProductsIdOf;
    // account => (productId => product)
    mapping(address => mapping(uint => EnteredProduct)) public productOf;
}

contract VDONStakingInterface is VDONStakingStorage {
    event Mint(address minter, uint mintAmount);
    event Redeem(address redeemer, uint DONRedeemAmount, uint ecoCNGRedeemAmount);
    event Withdraw(address withdrawer, uint withdrawAmount, address tokenAddress);
    event UpdateAdmin(address oldAdmin, address newAdmin);

    function mint(uint productInfoId, uint mintAmount) external returns (uint);

    function redeem(uint productId) external;

    function withdraw(address tokenAddress, uint amount) external returns (uint);

    function currentUsedRateOfInterestLimit(uint productInfoId) external view returns (uint);

    function createProductInfo(
        bool isActivate_,
        uint lockupTerm_,
        uint VDONExchangeRate_,
        uint interestLimitAmountOfDON_,
        uint interestRateOfDON_,
        uint interestLimitAmountOfecoCNG_,
        uint interestRateOfecoCNG_
    ) external returns (ProductInfo memory);

    function updateProductInfo(
        bool isActivate_,
        uint productInfoId,
        uint newLockupTerm,
        uint newVDONExchangeRate,
        uint newInterestLimitAmountOfDON,
        uint newInterestRateOfDON,
        uint newInterestLimitAmountOfecoCNG,
        uint newInterestRateOfecoCNG
    ) external returns (ProductInfo memory);

    function enteredProductOf(address account) external view returns (ProductView[] memory);
}
