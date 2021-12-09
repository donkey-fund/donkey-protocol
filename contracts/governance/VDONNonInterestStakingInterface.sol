// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.5.6;
pragma experimental ABIEncoderV2;

contract VDONNonInterestStakingStorage {
    bool internal _notEntered;

    address public admin;

    address DONAddress;

    address VDONAddress;

    struct ProductInfo {
        bool isActivate;
        // no-scale
        uint lockupTerm;
        // ex ) 1, 4
        uint VDONExchangeRate;
        // 1e18 scale 
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
        uint lockupTerm;
        uint VDONExchangeRate;
        uint totalPrincipalAmount;
        uint productInfoId;
        bool isActivate;
    }

    struct ProductView {
        uint startTime;
        uint releaseTime;
        uint principal;
        uint lockupTerm;
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

contract VDONNonInterestStakingInterface is VDONNonInterestStakingStorage {
    event Mint(address minter, uint mintAmount);
    event Redeem(address redeemer, uint DONRedeemAmount);
    event UpdateAdmin(address oldAdmin, address newAdmin);

    function mint(uint productInfoId, uint mintAmount) external returns (uint);

    function redeem(uint redeemProductId) external;

    function createProductInfo(
        bool isActivate_,
        uint lockupTerm_,
        uint VDONExchangeRate_
    ) external returns (ProductInfo memory);

    function updateProductInfo(
        bool isActivate_,
        uint productInfoId,
        uint newLockupTerm,
        uint newVDONExchangeRate
    ) external returns (ProductInfo memory);

    function enteredProductOf(address account) external view returns (ProductView[] memory);
}
