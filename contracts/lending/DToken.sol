// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.5.6;

// Original work from Compound: https://github.com/compound-finance/compound-protocol/blob/master/contracts/CToken.sol

import "./ControllerInterface.sol";
import "./DTokenInterface.sol";
import "./InterestRateModel.sol";
import "./Error.sol";
import "./IERC20.sol";

import "../common/Exponential.sol";
import "../common/upgradeable/Initializable.sol";

contract DToken is Initializable, DTokenInterface, Exponential, TokenErrorReporter {

    using MySafeMath for uint;

    struct MintLocalVars {
        Error err;
        MathError mathErr;
        uint exchangeRateMantissa;
        uint mintTokens;
        uint totalSupplyNew;
        uint accountBalancesNew;
        uint actualMintAmount;
        uint supplyPrincipalNew;
    }

    function initialize(ControllerInterface controller_, InterestRateModel interestRateModel_, uint initialExchangeRateMantissa_, string memory name_, string memory symbol_, bytes32 underlyingSymbol_, uint8 decimals_) public initializer {
        require(msg.sender == admin, "E1");
        require(accrualBlockNumber == 0 && borrowIndex == 0, "E2");

        initialExchangeRateMantissa = initialExchangeRateMantissa_;
        require(initialExchangeRateMantissa > 0, "E3");

        controller = controller_;

        accrualBlockNumber = getBlockNumber();
        borrowIndex = mantissaOne;

        uint err = _setInterestRateModelFresh(interestRateModel_);
        require(err == uint(Error.NO_ERROR), "E4");

        name = name_;
        symbol = symbol_;
        underlyingSymbol = underlyingSymbol_;
        decimals = decimals_;
        _notEntered = true;
    }

    function setAdmin(address payable newAdmin_) external {
        require(msg.sender == admin, 'E1');
        admin = newAdmin_;
        emit NewAdmin(admin);
    }

    function exchangeRateCurrent() public nonReentrant returns (uint) {
        require(accrueInterest() == uint(Error.NO_ERROR), "E5");
        return exchangeRateStored();
    }

    function exchangeRateStored() public view returns (uint) {
        (MathError err, uint result) = exchangeRateStoredInternal();
        require(err == MathError.NO_ERROR, "E68");
        return result;
    }

    function exchangeRateStoredInternal() internal view returns (MathError, uint) {
        uint _totalSupply = totalSupply;
        
        if (_totalSupply == 0) {
            return (MathError.NO_ERROR, initialExchangeRateMantissa);
        } else {
            uint totalCash = getCashPrior();
            uint cashPlusBorrowsMinusReserves;
            Exp memory exchangeRate;
            MathError mathErr;

            (mathErr, cashPlusBorrowsMinusReserves) = addThenSubUInt(totalCash, totalBorrows, totalReserves);
            if (mathErr != MathError.NO_ERROR) {
                return (mathErr, 0);
            }

            (mathErr, exchangeRate) = getExp(cashPlusBorrowsMinusReserves, _totalSupply);
            if (mathErr != MathError.NO_ERROR) {
                return (mathErr, 0);
            }

            return (MathError.NO_ERROR, exchangeRate.mantissa);
        }
    }

    function borrow(uint borrowAmount) external returns (uint) {
        return borrowInternal(borrowAmount);
    }

    function balanceOf(address owner) external view returns (uint256) {
        return accountBalances[owner];
    }

    function balanceOfUnderlying(address owner) external returns (uint) {
        Exp memory exchangeRate = Exp({mantissa: exchangeRateCurrent()});
        (MathError mErr, uint balance) = mulScalarTruncate(exchangeRate, accountBalances[owner]);
        require(mErr == MathError.NO_ERROR, "E69");
        return balance;
    }

    function transferTokens(address spender, address src, address dst, uint amount) internal returns (uint) {
        uint allowed = controller.transferAllowed(address(this), src, dst, amount);
        if (allowed != 0) {
            return failOpaque(Error.CONTROLLER_REJECTION, FailureInfo.TRANSFER_CONTROLLER_REJECTION, allowed);
        }
        if (src == dst) {
            return fail(Error.BAD_INPUT, FailureInfo.TRANSFER_NOT_ALLOWED);
        }

        uint startingAllowance = 0;
        if (spender == src) {
            startingAllowance = uint(-1);
        } else {
            startingAllowance = transferAllowances[src][spender];
        }

        MathError mathErr;
        uint allowanceNew;
        uint srcTokensNew;
        uint dstTokensNew;

        (mathErr, allowanceNew) = subUInt(startingAllowance, amount);
        require(mathErr == MathError.NO_ERROR, "E70");

        (mathErr, srcTokensNew) = subUInt(accountBalances[src], amount);
        require(mathErr == MathError.NO_ERROR, "E71");

        (mathErr, dstTokensNew) = addUInt(accountBalances[dst], amount);
        require(mathErr == MathError.NO_ERROR, "E72");

        accountBalances[src] = srcTokensNew;
        accountBalances[dst] = dstTokensNew;

        if (startingAllowance != uint(-1)) {
            transferAllowances[src][spender] = allowanceNew;
        }

        emit Transfer(src, dst, amount);

        return uint(Error.NO_ERROR);
    }

    function transfer(address recipient, uint amount) external nonReentrant returns (bool) {
        return transferTokens(msg.sender, msg.sender, recipient, amount) == uint(Error.NO_ERROR);
    }

    function transferFrom(address sender, address recipient, uint amount) external nonReentrant returns (bool) {
        return transferTokens(msg.sender, sender, recipient, amount) == uint(Error.NO_ERROR);
    }

    function mintFresh(address minter, uint mintAmount) internal nonReentrant returns (uint) {
        require(accrueInterest() == uint(Error.NO_ERROR), "E5");

        uint allowed = controller.mintAllowed(address(this), minter);
 
        require(allowed == 0, "E10");
        require(accrualBlockNumber == getBlockNumber(), "E18");

        MintLocalVars memory vars;

        (vars.mathErr, vars.exchangeRateMantissa) = exchangeRateStoredInternal();
        require(vars.mathErr == MathError.NO_ERROR, "E12");

        vars.actualMintAmount = doTransferIn(minter, mintAmount);

        (vars.mathErr, vars.mintTokens) = divScalarByExpTruncate(vars.actualMintAmount, Exp({mantissa: vars.exchangeRateMantissa}));
        require(vars.mathErr == MathError.NO_ERROR, "E13");

        {
        (vars.mathErr, vars.supplyPrincipalNew) = addUInt(supplyPrincipal[minter], vars.actualMintAmount);
        require(vars.mathErr == MathError.NO_ERROR, "E16");
        supplyPrincipal[minter] = vars.supplyPrincipalNew;
        }

        (vars.mathErr, vars.totalSupplyNew) = addUInt(totalSupply, vars.mintTokens);
        require(vars.mathErr == MathError.NO_ERROR, "E14");

        (vars.mathErr, vars.accountBalancesNew) = addUInt(accountBalances[minter], vars.mintTokens);
        require(vars.mathErr == MathError.NO_ERROR, "E15");
        
        totalSupply = vars.totalSupplyNew;
        accountBalances[minter] = vars.accountBalancesNew;

        emit Mint(minter, vars.actualMintAmount, vars.mintTokens);
        emit Transfer(address(this), minter, vars.mintTokens);

        return vars.actualMintAmount;
    }


    struct RedeemLocalVars {
        Error err;
        MathError mathErr;
        uint exchangeRateMantissa;
        uint allowed;
        uint redeemTokens;
        uint redeemAmount;
        uint totalSupplyNew;
        uint accountBalancesNew;
        uint supplyPrincipalNew;
        uint incomeUnderlying;
        uint redeemGap;
        uint balanceOfUnderlying;
        uint actualRedeemAmount;
    }

    function redeemUnderlying(uint redeemUnderlyingAmount) external returns (uint) {
        require(accrueInterest() == uint(Error.NO_ERROR), "E5");
        require(accrualBlockNumber == getBlockNumber(), "E33");
        return redeemFresh(msg.sender, redeemUnderlyingAmount);
    }

    function redeemUnderlyingMax() external returns (uint) {
        require(accrueInterest() == uint(Error.NO_ERROR), "E5");
        require(accrualBlockNumber == getBlockNumber(), "E33");
        (, uint result) = borrowBalanceStoredInternal(msg.sender);
        if (result == 0) {
            uint exited = controller.exitMarket(msg.sender);
            require(exited == uint(Error.NO_ERROR), "E73");
        }
        return redeemFresh(msg.sender, uint(-1));
    }

    function redeemFresh(address payable redeemer, uint redeemUnderlyingIn) internal nonReentrant returns (uint) {
        require(redeemUnderlyingIn != 0, "E34");

        RedeemLocalVars memory vars;

        (vars.mathErr, vars.exchangeRateMantissa) = exchangeRateStoredInternal();
        require(vars.mathErr == MathError.NO_ERROR, "E35");
        (MathError mErr, uint currentBalanceOfUnderlying) = mulScalarTruncate(Exp({mantissa: vars.exchangeRateMantissa}), accountBalances[redeemer]);
        require(mErr == MathError.NO_ERROR, "E36");

        /* If redeemUnderlyingIn == -1, redeemAmount = balanceOfUnderlying */
        if (redeemUnderlyingIn == uint(-1)) {
            vars.redeemAmount = currentBalanceOfUnderlying;
            vars.redeemTokens = accountBalances[redeemer];
        } else {
            vars.redeemAmount = redeemUnderlyingIn;
            (vars.mathErr, vars.redeemTokens) = divScalarByExpTruncate(vars.redeemAmount, Exp({mantissa: vars.exchangeRateMantissa}));
            require(vars.mathErr == MathError.NO_ERROR, "E37");
        }

        {
        if (currentBalanceOfUnderlying > supplyPrincipal[redeemer]) {
            (vars.mathErr, vars.incomeUnderlying) = subUInt(currentBalanceOfUnderlying, supplyPrincipal[redeemer]);
            require(vars.mathErr == MathError.NO_ERROR, "E38");
        } else {
            vars.incomeUnderlying = 0;
        }

        if (vars.redeemAmount >= vars.incomeUnderlying) {
            (vars.mathErr, vars.redeemGap) = subUInt(vars.redeemAmount, vars.incomeUnderlying);
            (vars.mathErr, vars.supplyPrincipalNew) = subUInt(supplyPrincipal[redeemer], vars.redeemGap);
            require(vars.mathErr == MathError.NO_ERROR, "E39");
            supplyPrincipal[redeemer] = vars.supplyPrincipalNew;
        }
        }

        vars.allowed = controller.redeemAllowed(address(this), redeemer, vars.redeemTokens);
        require(vars.allowed == 0, "E40");

        (vars.mathErr, vars.totalSupplyNew) = subUInt(totalSupply, vars.redeemTokens);
        require(vars.mathErr == MathError.NO_ERROR, "E41");

        (vars.mathErr, vars.accountBalancesNew) = subUInt(accountBalances[redeemer], vars.redeemTokens);
        require(vars.mathErr == MathError.NO_ERROR, "E42");

        require(getCashPrior() >= vars.redeemAmount, "E43");

        vars.actualRedeemAmount = doTransferOut(redeemer, vars.redeemAmount);
        emit Transfer(redeemer, address(this), vars.redeemTokens);

        totalSupply = vars.totalSupplyNew;
        accountBalances[redeemer] = vars.accountBalancesNew;
        emit Redeem(redeemer, vars.actualRedeemAmount);

        controller.redeemVerify(vars.actualRedeemAmount, vars.redeemTokens);

        return uint(Error.NO_ERROR);
    }
    
    function borrowInternal(uint borrowAmount) internal nonReentrant returns (uint) {
        require(accrueInterest() == uint(Error.NO_ERROR), "E5");

        return borrowFresh(msg.sender, borrowAmount);
    }

    function totalBorrowsCurrent() external nonReentrant returns (uint) {
        require(accrueInterest() == uint(Error.NO_ERROR), "E5");
        return totalBorrows;
    }

    struct BorrowLocalVars {
        MathError mathErr;
        uint accountBorrows;
        uint accountBorrowsNew;
        uint totalBorrowsNew;
        uint actualBorrowAmount;
        uint borrowPrincipalNew;
    }

    function borrowFresh(address payable borrower, uint borrowAmount) internal returns (uint) {
        uint allowed = controller.borrowAllowed(address(this), borrower, borrowAmount);
        require(allowed == 0, "E21");

        require(accrualBlockNumber == getBlockNumber(), "E22");
        require(getCashPrior() >= borrowAmount, "E23");

        BorrowLocalVars memory vars;

        (vars.mathErr, vars.accountBorrows) = borrowBalanceStoredInternal(borrower);
        require(vars.mathErr == MathError.NO_ERROR, "E24");

        (vars.mathErr, vars.accountBorrowsNew) = addUInt(vars.accountBorrows, borrowAmount);
        require(vars.mathErr == MathError.NO_ERROR, "E25");

        (vars.mathErr, vars.totalBorrowsNew) = addUInt(totalBorrows, borrowAmount);
        require(vars.mathErr == MathError.NO_ERROR, "E26");

        vars.actualBorrowAmount = doTransferOut(borrower, borrowAmount);

        vars.borrowPrincipalNew;

        accountBorrows[borrower].principal = vars.accountBorrowsNew;
        accountBorrows[borrower].interestIndex = borrowIndex;
        totalBorrows = vars.totalBorrowsNew;

        (vars.mathErr, vars.borrowPrincipalNew) = addUInt(borrowPrincipal[borrower], vars.actualBorrowAmount);
        require(vars.mathErr == MathError.NO_ERROR, "E27");
        borrowPrincipal[borrower] = vars.borrowPrincipalNew;

        emit Borrow(borrower, vars.actualBorrowAmount);
        emit Transfer(address(this), borrower, vars.actualBorrowAmount);

        return uint(Error.NO_ERROR);
    }


    function repayBorrowInternal(uint repayAmount) internal nonReentrant returns (uint, uint) {
        return repayBorrowFresh(msg.sender, msg.sender, repayAmount);
    }

    struct RepayBorrowLocalVars {
        Error err;
        MathError mathErr;
        uint repayAmount;
        uint borrowerIndex;
        uint accountBorrows;
        uint accountBorrowsNew;
        uint totalBorrowsNew;
        uint actualRepayAmount;
    }

    function repayBorrowFresh(address payer, address borrower, uint repayAmount) internal returns (uint, uint) {
        uint allowed = controller.repayBorrowAllowed(address(this), borrower);
        require(accrualBlockNumber == getBlockNumber(), "E28");

        require(allowed == 0, "E29");

        RepayBorrowLocalVars memory vars;

        vars.borrowerIndex = accountBorrows[borrower].interestIndex;

        (vars.mathErr, vars.accountBorrows) = borrowBalanceStoredInternal(borrower);
        require(vars.mathErr == MathError.NO_ERROR, "E30");

        if (repayAmount == uint(-1)) {
            vars.repayAmount = vars.accountBorrows;
        } else {
            vars.repayAmount = repayAmount;
        }

        vars.actualRepayAmount = doTransferIn(payer, vars.repayAmount);

        (vars.mathErr, vars.accountBorrowsNew) = subUInt(vars.accountBorrows, vars.actualRepayAmount);
        require(vars.mathErr == MathError.NO_ERROR, "E31");

        (vars.mathErr, vars.totalBorrowsNew) = subUInt(totalBorrows, vars.actualRepayAmount);
        require(vars.mathErr == MathError.NO_ERROR, "E32");

        borrowPrincipal[borrower] = vars.accountBorrowsNew;
        accountBorrows[borrower].principal = vars.accountBorrowsNew;
        accountBorrows[borrower].interestIndex = borrowIndex;
        totalBorrows = vars.totalBorrowsNew;

        if (repayAmount == uint(-1)) {
            if (accountBalances[borrower] == 0) {
                uint exited = controller.exitMarket(msg.sender);
                require(exited == uint(Error.NO_ERROR), "E73");
            }
        } 

        emit RepayBorrow(payer, borrower, vars.actualRepayAmount, vars.accountBorrowsNew, vars.totalBorrowsNew);

        return (uint(Error.NO_ERROR), vars.actualRepayAmount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        address sender = msg.sender;
        transferAllowances[sender][spender] = amount;

        emit Approval(sender, spender, amount);

        return true;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return transferAllowances[owner][spender];
    }

    function getBlockNumber() internal view returns (uint) {
        return block.number;
    }
    
    function getAccountSnapshot(address account) external view returns (uint, uint, uint, uint) {
        uint dTokenBalance = accountBalances[account];
        uint borrowBalance;
        uint exchangeRateMantissa;

        MathError mErr;

        (mErr, borrowBalance) = borrowBalanceStoredInternal(account);

        if (mErr != MathError.NO_ERROR) {
            return (uint(Error.MATH_ERROR), 0, 0, 0);
        }

        (mErr, exchangeRateMantissa) = exchangeRateStoredInternal();
        if (mErr != MathError.NO_ERROR) {
            return (uint(Error.MATH_ERROR), 0, 0, 0);
        }

        return (uint(Error.NO_ERROR), dTokenBalance, borrowBalance, exchangeRateMantissa);
    }

    function borrowBalanceCurrent(address account) external nonReentrant returns (uint) {
        require(accrueInterest() == uint(Error.NO_ERROR), "E5");
        return borrowBalanceStored(account);
    }

    function borrowBalanceStored(address account) public view returns (uint) {
        (MathError err, uint result) = borrowBalanceStoredInternal(account);
        require(err == MathError.NO_ERROR, "E74");
        return result;
    }

    function borrowBalanceStoredInternal(address account) internal view returns (MathError, uint) {
        MathError mathErr;
        uint principalTimesIndex;
        uint result;

        BorrowSnapshot storage borrowSnapshot = accountBorrows[account];

        if (borrowSnapshot.principal == 0) {
            return (MathError.NO_ERROR, 0);
        }

        (mathErr, principalTimesIndex) = mulUInt(borrowSnapshot.principal, borrowIndex);
        if (mathErr != MathError.NO_ERROR) {
            return (mathErr, 0);
        }

        (mathErr, result) = divUInt(principalTimesIndex, borrowSnapshot.interestIndex);
        if (mathErr != MathError.NO_ERROR) {
            return (mathErr, 0);
        }

        return (MathError.NO_ERROR, result);
    }

    function borrowRatePerBlock() external view returns (uint) {
        return interestRateModel.getBorrowRate(getCashPrior(), totalBorrows, totalReserves);
    }
    
    function _setReserveFactor(uint newReserveFactorMantissa) external nonReentrant returns (uint) {
        uint error = accrueInterest();
        require(error == uint(Error.NO_ERROR), "E5");
        // _setReserveFactorFresh emits reserve-factor-specific logs on errors, so we don't need to.
        return _setReserveFactorFresh(newReserveFactorMantissa);
    }

    function _setReserveFactorFresh(uint newReserveFactorMantissa) internal returns (uint) {
        require(msg.sender == admin, "E1");
        require(accrualBlockNumber == getBlockNumber(), "E7");
        require(newReserveFactorMantissa <= reserveFactorMaxMantissa, "E44");

        uint oldReserveFactorMantissa = reserveFactorMantissa;
        reserveFactorMantissa = newReserveFactorMantissa;

        emit NewReserveFactor(oldReserveFactorMantissa, newReserveFactorMantissa);

        return uint(Error.NO_ERROR);
    }

    function _setInterestRateModel(InterestRateModel newInterestRateModel) public returns (uint) {
        uint error = accrueInterest();
        require(error == uint(Error.NO_ERROR), "E5");
        return _setInterestRateModelFresh(newInterestRateModel);
    }

    function _setInterestRateModelFresh(InterestRateModel newInterestRateModel) internal returns (uint) {

        InterestRateModel oldInterestRateModel;

        require(msg.sender == admin, "E1");

        require(accrualBlockNumber == getBlockNumber(), "E7");

        oldInterestRateModel = interestRateModel;

        require(newInterestRateModel.isInterestRateModel(), "E45");

        interestRateModel = newInterestRateModel;

        return uint(Error.NO_ERROR);
    }

    function _addReservesInternal(uint addAmount) internal nonReentrant returns (uint) {
        uint error = accrueInterest();
        require(error == uint(Error.NO_ERROR), "E5");
        (error, ) = _addReservesFresh(addAmount);
        return error;
    }

    function _addReservesFresh(uint addAmount) internal returns (uint, uint) {
        uint totalReservesNew;
        uint actualAddAmount;

        require(accrualBlockNumber == getBlockNumber(), "E7");

        actualAddAmount = doTransferIn(msg.sender, addAmount);

        totalReservesNew = totalReserves + actualAddAmount;

        require(totalReservesNew >= totalReserves, "E46");

        totalReserves = totalReservesNew;

        emit ReservesAdded(msg.sender, actualAddAmount, totalReservesNew);

        return (uint(Error.NO_ERROR), actualAddAmount);
    }

    function _reduceReserves(uint reduceAmount) external returns (uint) {
        uint error = accrueInterest();
        require(error == uint(Error.NO_ERROR), "E5");
        return _reduceReservesFresh(reduceAmount);
    }

    function _reduceReservesFresh(uint reduceAmount) internal returns (uint) {
        uint totalReservesNew;

        require(msg.sender == admin, "E1");
        require(accrualBlockNumber == getBlockNumber(), "E7");

        require(getCashPrior() >= reduceAmount, "E21");
        require(reduceAmount <= totalReserves, "E47");

        totalReservesNew = totalReserves - reduceAmount;
        require(totalReservesNew <= totalReserves, "E48");

        totalReserves = totalReservesNew;

        // doTransferOut reverts if anything goes wrong, since we can't be sure if side effects occurred.
        uint actualReduceAmount = doTransferOut(admin, reduceAmount);

        emit ReservesReduced(admin, actualReduceAmount, totalReservesNew);

        return uint(Error.NO_ERROR);
    }

    function supplyRatePerBlock() external view returns (uint) {
        return interestRateModel.getSupplyRate(getCashPrior(), totalBorrows, totalReserves, reserveFactorMantissa);
    }

    function getCash() external view returns (uint) {
        return getCashPrior();
    }

    function liquidateBorrowInternal(address borrower, uint repayAmount, DTokenInterface dTokenCollateral) internal nonReentrant returns (uint, uint) {
        uint error = accrueInterest();
        require(error == uint(Error.NO_ERROR), "E5");

        error = dTokenCollateral.accrueInterest();
        require(error == uint(Error.NO_ERROR), "E5");

        return liquidateBorrowFresh(msg.sender, borrower, repayAmount, dTokenCollateral);
    }

    function liquidateBorrowFresh(address liquidator, address borrower, uint repayAmount, DTokenInterface dTokenCollateral) internal returns (uint, uint) {
        uint allowed = controller.liquidateBorrowAllowed(address(this), address(dTokenCollateral), borrower, liquidator, repayAmount);

        require(allowed == 0, "E49");
        require(accrualBlockNumber == getBlockNumber(), "E7");
        require(dTokenCollateral.accrualBlockNumber() == getBlockNumber(), "E7");
        require(borrower != liquidator, "E50");
        require(repayAmount != 0, "E51");
        require(repayAmount != uint(-1), "E52");

        (uint repayBorrowError, uint actualRepayAmount) = repayBorrowFresh(liquidator, borrower, repayAmount);
        require(repayBorrowError == uint(Error.NO_ERROR), "E53");

        (uint amountSeizeError, uint seizeTokens) = controller.liquidateCalculateSeizeTokens(address(this), address(dTokenCollateral), actualRepayAmount);
        require(amountSeizeError == uint(Error.NO_ERROR), "E54");
        require(dTokenCollateral.balanceOf(borrower) >= seizeTokens, "E55");

        {
        uint seizeError;

        if (address(dTokenCollateral) == address(this)) {
            seizeError = seizeInternal(address(this), liquidator, borrower, seizeTokens);
        } else {
            seizeError = dTokenCollateral.seize(liquidator, borrower, seizeTokens);
        }
        require(seizeError == uint(Error.NO_ERROR), "E56");
        }

        emit LiquidateBorrow(liquidator, borrower, actualRepayAmount, address(dTokenCollateral), seizeTokens);

        return (uint(Error.NO_ERROR), actualRepayAmount);
    }

    function repayBorrowBehalfInternal(address borrower, uint repayAmount) internal nonReentrant returns (uint, uint) {
        uint error = accrueInterest();
        if (error != uint(Error.NO_ERROR)) {
            return (fail(Error(error), FailureInfo.REPAY_BEHALF_ACCRUE_INTEREST_FAILED), 0);
        }
        return repayBorrowFresh(msg.sender, borrower, repayAmount);
    }

    function seize(address liquidator, address borrower, uint seizeTokens) external nonReentrant returns (uint) {
        return seizeInternal(msg.sender, liquidator, borrower, seizeTokens);
    }

    function seizeInternal(address seizerToken, address liquidator, address borrower, uint seizeTokens) internal returns (uint) {
        uint allowed = controller.seizeAllowed(address(this), seizerToken, liquidator, borrower);
        require(allowed == 0, "E57");

        require(borrower != liquidator, "E50");

        MathError mathErr;
        uint borrowerTokensNew;
        uint liquidatorTokensNew;

        (mathErr, borrowerTokensNew) = subUInt(accountBalances[borrower], seizeTokens);
        require(mathErr == MathError.NO_ERROR, "E58");

        (mathErr, liquidatorTokensNew) = addUInt(accountBalances[liquidator], seizeTokens);
        require(mathErr == MathError.NO_ERROR, "E59");

        accountBalances[borrower] = borrowerTokensNew;
        accountBalances[liquidator] = liquidatorTokensNew;

        /*
           currently unused
        {
        (, uint borrowBalance) = borrowBalanceStoredInternal(borrower);
        if (accountBalances[borrower] == 0 && borrowBalance == 0) {
            uint exited = controller.exitMarket(borrower);
            require(exited == uint(Error.NO_ERROR), "E73");
        }
        }
        */

        {
        uint supplyPrincipalNew;
        uint borrowerSupplyPrincipalNew;
        uint exchangeRateMantissa;
        uint currentBalanceOfUnderlying;

        (mathErr, exchangeRateMantissa) = exchangeRateStoredInternal();
        require(mathErr == MathError.NO_ERROR, "E35");
        (mathErr, currentBalanceOfUnderlying) = mulScalarTruncate(Exp({mantissa: exchangeRateMantissa}), seizeTokens);

        (mathErr, supplyPrincipalNew) = addUInt(supplyPrincipal[liquidator], currentBalanceOfUnderlying);
        require(mathErr == MathError.NO_ERROR, "E16");
        supplyPrincipal[liquidator] = supplyPrincipalNew;

        (mathErr, borrowerSupplyPrincipalNew) = subUInt(supplyPrincipal[borrower], currentBalanceOfUnderlying);
        require(mathErr == MathError.NO_ERROR, "E16");
        supplyPrincipal[borrower] = borrowerSupplyPrincipalNew;
        }

        emit Transfer(borrower, liquidator, seizeTokens);

        return uint(Error.NO_ERROR);
    }    

    function accrueInterest() public returns (uint) {
        uint currentBlockNumber = getBlockNumber();
        uint accrualBlockNumberPrior = accrualBlockNumber;

        if (accrualBlockNumberPrior == currentBlockNumber) {
            return uint(Error.NO_ERROR);
        }

        uint cashPrior = getCashPrior();
        uint borrowsPrior = totalBorrows;
        uint reservesPrior = totalReserves;
        uint borrowIndexPrior = borrowIndex;

        uint borrowRateMantissa = interestRateModel.getBorrowRate(cashPrior, borrowsPrior, reservesPrior);
        require(borrowRateMantissa <= borrowRateMaxMantissa, "E60");

        (MathError mathErr, uint blockDelta) = subUInt(currentBlockNumber, accrualBlockNumberPrior);
        require(mathErr == MathError.NO_ERROR, "E61");

        Exp memory simpleInterestFactor;
        uint interestAccumulated;
        uint totalBorrowsNew;
        uint totalReservesNew;
        uint borrowIndexNew;

        (mathErr, simpleInterestFactor) = mulScalar(Exp({mantissa: borrowRateMantissa}), blockDelta);
        require(mathErr == MathError.NO_ERROR, "E62");

        (mathErr, interestAccumulated) = mulScalarTruncate(simpleInterestFactor, borrowsPrior);
        require(mathErr == MathError.NO_ERROR, "E63");

        (mathErr, totalBorrowsNew) = addUInt(interestAccumulated, borrowsPrior);
        require(mathErr == MathError.NO_ERROR, "E64");

        (mathErr, totalReservesNew) = mulScalarTruncateAddUInt(Exp({mantissa: reserveFactorMantissa}), interestAccumulated, reservesPrior);
        require(mathErr == MathError.NO_ERROR, "E65");

        (mathErr, borrowIndexNew) = mulScalarTruncateAddUInt(simpleInterestFactor, borrowIndexPrior, borrowIndexPrior);
        require(mathErr == MathError.NO_ERROR, "E66");

        accrualBlockNumber = currentBlockNumber;
        borrowIndex = borrowIndexNew;
        totalBorrows = totalBorrowsNew;
        totalReserves = totalReservesNew;

        return uint(Error.NO_ERROR);
    }

    function setController(ControllerInterface newController) external returns (uint) {
        require(msg.sender == admin, "E1");

        controller = newController;

        emit NewController(newController);

        return uint(Error.NO_ERROR);
    }

    modifier nonReentrant() {
        require(_notEntered, "E67");
        _notEntered = false;
        _;
        _notEntered = true; // get a gas-refund post-Istanbul
    }

    function doTransferIn(address sender, uint amount) internal returns (uint);
    function doTransferOut(address payable recipient, uint amount) internal returns (uint);
    function getCashPrior() internal view returns (uint);
}
