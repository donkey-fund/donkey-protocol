// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.5.6;

// Original work from Compound: https://github.com/compound-finance/compound-protocol/blob/master/contracts/ComptrollerInterface.sol

import "./DToken.sol";

contract ControllerInterface {
    bool public constant isController = true;

    function enterMarkets(address dToken, address account) internal returns (uint);
    function exitMarket(address account) external returns (uint);

    function mintAllowed(address dToken, address minter) external returns (uint);
    function redeemAllowed(address dToken, address redeemer, uint redeemAmount) external returns (uint);
    function redeemVerify(uint redeemAmount, uint redeemTokens) external;
    function borrowAllowed(address dToken, address payable borrower, uint borrowAmount) external returns (uint);
    function transferAllowed(address dToken, address src, address dst, uint transferTokens) external returns (uint);
    function repayBorrowAllowed(
        address dToken,
        address borrower) external returns (uint);
    function liquidateBorrowAllowed(
        address dTokenBorrowed,
        address dTokenCollateral,
        address borrower,
        address liquidator,
        uint repayAmount) external returns (uint);
    function liquidateCalculateSeizeTokens(
        address dTokenBorrowed,
        address dTokenCollateral,
        uint repayAmount) external view returns (uint, uint);
    function seizeAllowed(
        address dTokenCollateral,
        address dTokenBorrowed,
        address liquidator,
        address borrower) external returns (uint);
    function getAccountLiquidity(
        address account,
        bool isProtectedCall
    ) external view returns (uint, uint, uint);
}

