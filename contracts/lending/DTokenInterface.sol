// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.5.6;

// Original work from Compound: https://github.com/compound-finance/compound-protocol/blob/master/contracts/CTokenInterface.sol

import "./ControllerInterface.sol";
import "./InterestRateModel.sol";

contract DTokenStorage {

    bool public constant isDToken = true;
    bool internal _notEntered;

    ControllerInterface public controller;
    InterestRateModel public interestRateModel;

    bytes32 public underlyingSymbol;
    string public name;
    string public symbol;
    uint8 public decimals;

    address payable public admin;

    uint public totalBorrows;
    uint public totalSupply;

    uint public accrualBlockNumber;
    uint public borrowIndex;
    uint public totalReserves;
    uint public reserveFactorMantissa;
    uint internal initialExchangeRateMantissa;

    uint internal constant borrowRateMaxMantissa = 0.0005e16;
    uint internal constant reserveFactorMaxMantissa = 1e18;

    mapping (address => uint) internal accountBalances;
    mapping (address => mapping (address => uint)) internal transferAllowances;

    mapping (address => uint) public supplyPrincipal;
    mapping (address => uint) public borrowPrincipal;

    struct BorrowSnapshot {
        uint principal;
        uint interestIndex;
    }
    mapping (address => BorrowSnapshot) internal accountBorrows;
}

contract DTokenInterface is DTokenStorage {
    event NewAdmin(address newAdmin);
    event Mint(address minter, uint mintAmount, uint mintTokens);
    event RepayBorrow(address payer, address borrower, uint repayAmount, uint accountBorrows, uint totalBorrows);
    event Borrow(address borrower, uint borrowAmount);
    event Redeem(address redeemer, uint redeemAmount);
    event Transfer(address indexed sender, address indexed recipient, uint amount);
    event Approval(address indexed owner, address indexed spender, uint amount);
    event Failure(uint error, uint info, uint detail);
    event LiquidateBorrow(address liquidator, address borrower, uint repayAmount, address dTokenCollateral, uint seizeTokens);
    event NewReserveFactor(uint oldReserveFactorMantissa, uint newReserveFactorMantissa);
    event ReservesAdded(address benefactor, uint addAmount, uint newTotalReserves);
    event ReservesReduced(address admin, uint reduceAmount, uint newTotalReserves);
    event NewController(ControllerInterface newController);

    function transfer(address recipient, uint amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint amount) external returns (bool);
    function balanceOf(address owner) external view returns (uint);
    function approve(address spender, uint amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint);
    function getAccountSnapshot(address account) external view returns (uint, uint, uint, uint);
    function balanceOfUnderlying(address owner) external returns (uint);
    function accrueInterest() public returns (uint);
    function seize(address liquidator, address borrower, uint seizeTokens) external returns (uint);
}

contract DErc20Interface {
    address public underlying;

    function mint(uint mintAmount) external returns (uint);

    function repayBorrow(uint repayAmount) external payable returns (uint, uint);

    function liquidateBorrow(address borrower, uint repayAmount, DTokenInterface dTokenCollateral) external returns (uint);

    function repayBorrowBehalf(address borrower, uint repayAmount) external returns (uint);
    /*** Admin Functions ***/
    function _addReserves(uint addAmount) external returns (uint);
}

