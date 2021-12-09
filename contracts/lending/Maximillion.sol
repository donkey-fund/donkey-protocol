// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.5.6;

// Original work from Compound: https://github.com/compound-finance/compound-protocol/blob/master/contracts/Maximillion.sol

import "./DEther.sol";
import "./Error.sol";

import "../common/upgradeable/Initializable.sol";
import "../common/CarefulMath.sol";
import "../common/Exponential.sol";

contract Maximillion is Initializable, Exponential, TokenErrorReporter {
    DEther public dEther;

    function initialize(DEther dEther_) public initializer {
        dEther = dEther_;
    }

    function repayBehalf(address borrower) public payable {
        repayBehalfExplicit(borrower, dEther);
    }

    function repayBehalfExplicit(address borrower, DEther dEther_) public payable {
        uint received = msg.value;
        uint borrows = dEther_.borrowBalanceCurrent(borrower);
        if (received > borrows) {
            dEther_.repayBorrowBehalf.value(borrows)(borrower);
            (MathError mathErr, uint subResult) = subUInt(received, borrows);
            require(mathErr == MathError.NO_ERROR, 'MATH_ERROR');
            msg.sender.transfer(subResult);
        } else {
            dEther_.repayBorrowBehalf.value(received)(borrower);
        }
    }
}
