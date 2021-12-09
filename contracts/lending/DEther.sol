// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.5.6;

// Original work from Compound: https://github.com/compound-finance/compound-protocol/blob/master/contracts/CEther.sol

import "./DToken.sol";

contract DEther is Initializable, DToken {
    function initialize(
                ControllerInterface controller_,
                InterestRateModel interestRateModel_,
                uint initialExchangeRateMantissa_,
                string memory name_,
                string memory symbol_,
                bytes32 underlyingSymbol_,
                uint8 decimals_) public initializer {
        admin = msg.sender;
        DToken.initialize(controller_, interestRateModel_, initialExchangeRateMantissa_, name_, symbol_, underlyingSymbol_, decimals_);
    }

    function () external payable {
        mintFresh(msg.sender, msg.value);
    }

    function mint() external payable returns (uint actualMintAmount) {
        return mintFresh(msg.sender, msg.value);
    }
    
    function repayBorrow() external payable returns (uint, uint) {
        require(accrueInterest() == uint(Error.NO_ERROR), "E5");
        require(accrualBlockNumber == getBlockNumber(), "E7");
        return repayBorrowInternal(msg.value);
    }

    function repayBorrowBehalf(address borrower) external payable {
        (uint err,) = repayBorrowBehalfInternal(borrower, msg.value);
        requireNoError(err, "E75");
    }

    function liquidateBorrow(address borrower, DToken dTokenCollateral) external payable {
        (uint err,) = liquidateBorrowInternal(borrower, msg.value, dTokenCollateral);
        requireNoError(err, "E76");
    }

    function getCashPrior() internal view returns (uint) {
        (MathError err, uint startingBalance) = subUInt(address(this).balance, msg.value);
        require(err == MathError.NO_ERROR);
        return startingBalance;
    }    

    function doTransferIn(address sender, uint amount) internal returns (uint) {
        require(msg.sender == sender, "E77");
        require(msg.value == amount, "E78");

        return amount;
    }

    function doTransferOut(address payable recipient, uint amount) internal returns (uint) {
        recipient.transfer(amount);

        return amount;
    }

    function _addReserves() external payable returns (uint) {
        return _addReservesInternal(msg.value);
    }

    function requireNoError(uint errCode, string memory message) internal pure {
        if (errCode == uint(Error.NO_ERROR)) {
            return;
        }

        bytes memory fullMessage = new bytes(bytes(message).length + 5);
        uint i;

        for (i = 0; i < bytes(message).length; i++) {
            fullMessage[i] = bytes(message)[i];
        }

        fullMessage[i+0] = byte(uint8(32));
        fullMessage[i+1] = byte(uint8(40));
        fullMessage[i+2] = byte(uint8(48 + ( errCode / 10 )));
        fullMessage[i+3] = byte(uint8(48 + ( errCode % 10 )));
        fullMessage[i+4] = byte(uint8(41));

        require(errCode == uint(Error.NO_ERROR), string(fullMessage));
    }

}
