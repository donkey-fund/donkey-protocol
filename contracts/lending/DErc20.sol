// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.5.6;

// Original work from Compound: https://github.com/compound-finance/compound-protocol/blob/master/contracts/CErc20.sol

import "./DToken.sol";

contract DErc20 is Initializable, DToken, DErc20Interface {
    function initialize(
                ControllerInterface controller_,
                InterestRateModel interestRateModel_,
                uint initialExchangeRateMantissa_,
                address underlying_,
                string memory name_,
                string memory symbol_,
                bytes32 underlyingSymbol_,
                uint8 decimals_) public initializer {
        admin = msg.sender;
        underlying = underlying_;
        DToken.initialize(controller_, interestRateModel_, initialExchangeRateMantissa_, name_, symbol_, underlyingSymbol_, decimals_);
    }

    function mint(uint mintAmount) external returns (uint actualMintAmount) {
        return mintFresh(msg.sender, mintAmount);
    }

    function liquidateBorrow(address borrower, uint repayAmount, DTokenInterface dTokenCollateral) external returns (uint) {
        (uint err,) = liquidateBorrowInternal(borrower, repayAmount, dTokenCollateral);
        return err;
    }

    function repayBorrow(uint repayAmount) external payable returns (uint, uint) {
        require(accrueInterest() == uint(Error.NO_ERROR), "E5");
        return repayBorrowInternal(repayAmount);
    }

    function repayBorrowBehalf(address borrower, uint repayAmount) external returns (uint) {
        (uint err,) = repayBorrowBehalfInternal(borrower, repayAmount);
        return err;
    }

    function doTransferIn(address sender, uint amount) internal returns (uint) {
        IERC20 token = IERC20(underlying);

        uint balanceBeforeTransfer = IERC20(underlying).balanceOf(address(this));
        token.transferFrom(sender, address(this), amount);

        bool success;
        assembly {
            switch returndatasize()
                case 0 {                       // This is a non-standard ERC-20
                    success := not(0)          // set success to true
                }
                case 32 {                      // This is a compliant ERC-20
                    returndatacopy(0, 0, 32)
                    success := mload(0)        // Set `success = returndata` of external call
                }
                default {                      // This is an excessively non-compliant ERC-20, revert.
                    revert(0, 0)
                }
        }
        require(success, "E79");

        uint balanceAfterTransfer = IERC20(underlying).balanceOf(address(this));
        require(balanceAfterTransfer >= balanceBeforeTransfer , "E80");

        return balanceAfterTransfer - balanceBeforeTransfer;
    }

    function doTransferOut(address payable recipient, uint amount) internal returns (uint) {
        IERC20 token = IERC20(underlying);
        token.transfer(recipient, amount);

        bool success;
        assembly {
            switch returndatasize()
                case 0 {                      // This is a non-standard ERC-20
                    success := not(0)          // set success to true
                }
                case 32 {                     // This is a complaint ERC-20
                    returndatacopy(0, 0, 32)
                    success := mload(0)        // Set `success = returndata` of external call
                }
                default {                     // This is an excessively non-compliant ERC-20, revert.
                    revert(0, 0)
                }
        }
        require(success, "E81");
        return amount;
    }

    function getCashPrior() internal view returns (uint) {
        return IERC20(underlying).balanceOf(address(this));
    }

    function _addReserves(uint addAmount) external returns (uint) {
        return _addReservesInternal(addAmount);
    }
}
