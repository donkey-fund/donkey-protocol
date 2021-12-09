// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.5.6;

// Original work from Compound: https://github.com/compound-finance/compound-protocol/blob/master/contracts/Comptroller.sol

import "./DToken.sol";
import "./ControllerInterface.sol";
import "./ControllerStorage.sol";
import "./Error.sol";

import "../Donkey.sol";

/**
 * @title Donkey's Controller Contract for lending
 * @notice Controller Contract for lending
 * @author Donkey
 */

contract Controller is Initializable, ControllerInterface, ControllerStorage, Exponential, ControllerErrorReport {
    event MarketListed(DToken dToken);
    event MarketEntered(DToken dToken, address account);
    event MarketExited(DToken dToken, address account);
    event ActionPaused(DToken dToken, string action, bool pauseState);
    event NewAdmin(address newAdmin);
    event NewBorrowCap(DToken indexed dToken, uint newBorrowCap);
    event NewCollateralFactor(DToken dToken, uint oldCollateralFactorMantissa, uint newCollateralFactorMantissa);
    event NewCloseFactor(uint oldCloseFactorMantissa, uint newCloseFactorMantissa);
    event NewPriceOracle(PriceOracle newPriceOracle);
    event NewGuardian(address newGuardianAddress);

    event DistributeSupplierDonkey(DToken indexed dToken, address indexed supplier, uint donkeyDelta, uint donkeySupplyIndex);
    event DistributeBorrowerDonkey(DToken indexed dToken, address indexed borrower, uint donkeyDelta, uint donkeyBorrowIndex);

    uint224 public constant donkeyInitialIndex = 1e36;
    uint internal constant closeFactorMinMantissa = 0.05e18; // 0.05
    uint internal constant closeFactorMaxMantissa = 0.9e18; // 0.9
    uint internal constant collateralFactorMaxMantissa = 0.9e18; // 0.9

    function initialize(address admin_, address donkeyAddress_) public initializer {
        admin = admin_;
        DONKEY_ADDRESS = donkeyAddress_;
    }

    function setAdmin(address newAdmin_) external {
        require(msg.sender == admin, 'E1');
        admin = newAdmin_;
        emit NewAdmin(admin);
    }

    function enterMarkets(address dToken, address account) internal returns (uint) {
        DToken asset = DToken(dToken);
        return uint(addToMarketInternal(asset, account));
    }

    function exitMarket(address account) external returns (uint) {
        DToken dToken = DToken(msg.sender);
        (uint oErr, uint tokensHeld, uint amountOwed, ) = dToken.getAccountSnapshot(account);
        require(oErr == 0, 'E82');

        if (amountOwed != 0) {
            return fail(Error.NONZERO_BORROW_BALANCE, FailureInfo.EXIT_MARKET_BALANCE_OWED);
        }

        uint allowed = redeemAllowedInternal(address(msg.sender), account, tokensHeld);
        if (allowed != 0) {
            return failOpaque(Error.REJECTION, FailureInfo.EXIT_MARKET_REJECTION, allowed);
        }

        Market storage marketToExit = markets[address(dToken)];

        if (!marketToExit.accountMembership[account]) {
            return uint(Error.NO_ERROR);
        }

        delete marketToExit.accountMembership[account];

        DToken[] memory userAssetList = accountAssets[account];
        uint len = userAssetList.length;
        uint assetIndex = len;
        for (uint i = 0; i < len; i++) {
            if (userAssetList[i] == dToken) {
                assetIndex = i;
                break;
            }
        }

        assert(assetIndex < len);

        DToken[] storage storedList = accountAssets[account];
        storedList[assetIndex] = storedList[storedList.length - 1];
        storedList.length--;

        emit MarketExited(dToken, account);

        return uint(Error.NO_ERROR);
    }
 
    /*
    function getAccountMembership(DToken dToken, address account) view external returns (bool) {
        return markets[address(dToken)].accountMembership[account];
    }
    */

    function addToMarketInternal(DToken dToken, address borrower) internal returns (Error) {
        Market storage marketToJoin = markets[address(dToken)];

        if (!marketToJoin.isListed) {
            return Error.MARKET_NOT_LISTED;
        }

        if (marketToJoin.accountMembership[borrower]) {
            return Error.NO_ERROR;
        }

        marketToJoin.accountMembership[borrower] = true;
        accountAssets[borrower].push(dToken);

        emit MarketEntered(dToken, borrower);

        return Error.NO_ERROR;
    }

    function _addMarketInternal(address dToken) internal {
        for (uint i = 0; i < allMarkets.length; i ++) {
            require(allMarkets[i] != DToken(dToken), 'E83');
        }
        allMarkets.push(DToken(dToken));
    }

    function _setMarketBorrowCaps(DToken[] calldata dTokens, uint[] calldata newBorrowCaps) external {
    	require(msg.sender == admin, 'E1'); 

        uint numMarkets = dTokens.length;
        uint numBorrowCaps = newBorrowCaps.length;

        require(numMarkets != 0 && numMarkets == numBorrowCaps, 'E84');

        for(uint i = 0; i < numMarkets; i++) {
            borrowCaps[address(dTokens[i])] = newBorrowCaps[i];
            emit NewBorrowCap(dTokens[i], newBorrowCaps[i]);
        }
    }

    function redeemAllowed(address dToken, address redeemer, uint redeemAmount) external returns (uint) {
        require(!oracleGuardianPaused[dToken], "E85");
        uint allowed = redeemAllowedInternal(dToken, redeemer, redeemAmount);
        require(allowed == uint(Error.NO_ERROR), 'E40');

        updateDonkeySupplyIndex(dToken);
        distributeSupplierDonkey(dToken, redeemer);

        return uint(Error.NO_ERROR);
    }

    function redeemAllowedInternal(address dToken, address redeemer, uint redeemAmount) internal view returns (uint) {
        require(markets[dToken].isListed, 'E86');

        if (!markets[dToken].accountMembership[redeemer]) {
            return uint(Error.NO_ERROR);
        }

        (Error err, , uint shortfall) = getHypotheticalAccountLiquidityInternal(redeemer, DToken(dToken), redeemAmount, 0, true);
        if (err != Error.NO_ERROR) {
            return uint(err);
        }

        require(shortfall <= 0, 'E100');

        return uint(Error.NO_ERROR);
    }

    function transferAllowed(address dToken, address src, address dst, uint transferTokens) external returns (uint) {
        require(!transferGuardianPaused, 'E87');

        uint allowed = redeemAllowedInternal(dToken, src, transferTokens);
        if (allowed != uint(Error.NO_ERROR)) {
           return allowed;
        }

        updateDonkeySupplyIndex(dToken);
        distributeSupplierDonkey(dToken, src);
        distributeSupplierDonkey(dToken, dst);

        return uint(Error.NO_ERROR);
    }

    function mintAllowed(address dToken, address minter) external returns (uint) {
        require(!isMintPaused[dToken], 'E88');
        require(markets[dToken].isListed, 'E86');
        uint enteredMarket = enterMarkets(dToken, minter);
        require(enteredMarket == uint(Error.NO_ERROR), 'E89');

        updateDonkeySupplyIndex(dToken);
        distributeSupplierDonkey(dToken, minter);

        return uint(Error.NO_ERROR);
    }

    function setMintPaused(DToken dToken, bool state) external returns (bool) {
        require(msg.sender == admin || isPauseGuardian[msg.sender] == true, 'E1');
        require(markets[address(dToken)].isListed, 'E86');

        isMintPaused[address(dToken)] = state;
        emit ActionPaused(dToken, "Mint", state);
        return state;
    }

    function setOracleGuardianPaused(DToken[] calldata dTokens, bool state) external returns (bool) {
        require(msg.sender == admin || isPauseGuardian[msg.sender] == true, "E1");
        uint len = dTokens.length;
        for (uint i = 0 ; i < len ; i+=1) {
            oracleGuardianPaused[address(dTokens[i])] = state;
        }
        return state;
    }

    function _supportMarket(DToken dToken) external returns (uint) {
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SUPPORT_MARKET_OWNER_CHECK);
        }

        if (markets[address(dToken)].isListed) {
            return fail(Error.MARKET_ALREADY_LISTED, FailureInfo.SUPPORT_MARKET_EXISTS);
        }

        dToken.isDToken();

        markets[address(dToken)] = Market({isListed: true, isDonkeyed: false, collateralFactorMantissa: 0});

        _addMarketInternal(address(dToken));

        emit MarketListed(dToken);

        return uint(Error.NO_ERROR);
    }

    /*
    // currently unused
    function setProtectedAssets(address[] calldata dTokens, bool state) external {
        require(msg.sender == admin || isPauseGuardian[msg.sender] == true, 'E1');
        uint len = dTokens.length;
        for(uint i = 0 ; i < len ; i+=1) {
            protectedAssets[dTokens[i]] = state;
        }
    }
    */

    function borrowAllowed(address dToken, address payable borrower, uint borrowAmount) external returns (uint) {
        require(!oracleGuardianPaused[dToken], "E90");
        require(!isBorrowPaused[dToken], 'E91');
        require(markets[dToken].isListed, 'E86');
        
        if (!markets[dToken].accountMembership[borrower]) {
            require(msg.sender == dToken, 'E1');

            Error err = addToMarketInternal(DToken(dToken), borrower);
            if (err != Error.NO_ERROR) {
                return uint(err);
            }

            require(markets[dToken].accountMembership[borrower], 'E89');
        }

        {
        uint borrowCap = borrowCaps[dToken];
        if (borrowCap != 0) {
            uint totalBorrows = DToken(dToken).totalBorrows();
            uint nextTotalBorrows = add_(totalBorrows, borrowAmount);
            require(nextTotalBorrows < borrowCap, 'E92');
        }
        }
        
        (Error err, , uint shortfall) = getHypotheticalAccountLiquidityInternal(borrower, DToken(dToken), 0, borrowAmount, true);

        if (err != Error.NO_ERROR) {
          return uint(err);
        }

        require(shortfall <= 0, 'E100');
        
        Exp memory borrowIndex = Exp({mantissa: DToken(dToken).borrowIndex()});

        updateDonkeyBorrowIndex(dToken, borrowIndex);
        distributeBorrowerDonkey(dToken, borrower, borrowIndex);

        return uint(Error.NO_ERROR);
    }

    function repayBorrowAllowed(address dToken, address borrower) external returns (uint) {
        require(markets[dToken].isListed, 'E86');

        Exp memory borrowIndex = Exp({mantissa : DToken(dToken).borrowIndex()});
        updateDonkeyBorrowIndex(dToken, borrowIndex);
        distributeBorrowerDonkey(dToken, borrower, borrowIndex);
        return uint(Error.NO_ERROR);
    }

    function setPauseGuardian(address newGuardianAddress, bool state) external returns (uint) {
        require(msg.sender == admin, 'E1');
        isPauseGuardian[newGuardianAddress] = state;
        emit NewGuardian(newGuardianAddress);
        return uint(Error.NO_ERROR);
    }

    function setBorrowPaused(DToken dToken, bool state) external returns (bool) {
        require(markets[address(dToken)].isListed, 'E86');
        require(msg.sender == admin || isPauseGuardian[msg.sender] == true, 'E1');

        isBorrowPaused[address(dToken)] = state;
        emit ActionPaused(dToken, "Borrow", state);
        return state;
    }

    struct AccountLiquidityLocalVars {
        uint sumCollateral;
        uint sumBorrowPlusEffects;
        uint dTokenBalance;
        uint borrowBalance;
        uint exchangeRateMantissa;
        uint oraclePriceMantissa;
        Exp collateralFactor;
        Exp exchangeRate;
        Exp oraclePrice;
        Exp tokensToDenom;
    }

   function _setSeizePaused(DToken[] calldata dTokens, bool state) external returns (bool) {
        require(isPauseGuardian[msg.sender] == true || msg.sender == admin, 'E1');

        uint len = dTokens.length;
        for (uint i = 0 ; i < len ; i+=1) {
            isSeizePaused[address(dTokens[i])] = state;
        }
        return state;
    }

    function seizeAllowed(
        address dTokenCollateral,
        address dTokenBorrowed,
        address liquidator,
        address borrower) external returns (uint) {
        require(!isSeizePaused[dTokenCollateral], 'E98');
        require(markets[dTokenCollateral].isListed, 'E86');
        require(markets[dTokenBorrowed].isListed, 'E86');
        require(DToken(dTokenCollateral).controller() == DToken(dTokenBorrowed).controller(), 'E93');

        updateDonkeySupplyIndex(dTokenCollateral);
        distributeSupplierDonkey(dTokenCollateral, borrower);
        distributeSupplierDonkey(dTokenCollateral, liquidator);

        return uint(Error.NO_ERROR);
    }

    function liquidateCalculateSeizeTokens(address dTokenBorrowed, address dTokenCollateral, uint actualRepayAmount) external view returns (uint, uint) {
        uint priceBorrowedMantissa = priceOracle.getUnderlyingPrice(DToken(dTokenBorrowed).underlyingSymbol());
        uint priceCollateralMantissa = priceOracle.getUnderlyingPrice(DToken(dTokenCollateral).underlyingSymbol());

        if (priceBorrowedMantissa == 0 || priceCollateralMantissa == 0) {
            return (uint(Error.PRICE_ERROR), 0);
        }

        uint exchangeRateMantissa = DToken(dTokenCollateral).exchangeRateStored(); // Note: reverts on error
        uint seizeTokens;
        Exp memory numerator;
        Exp memory denominator;
        Exp memory ratio;

        numerator = mul_(Exp({mantissa: liquidationIncentiveMantissa[dTokenCollateral]}), Exp({mantissa: priceBorrowedMantissa}));
        denominator = mul_(Exp({mantissa: priceCollateralMantissa}), Exp({mantissa: exchangeRateMantissa}));
        ratio = div_(numerator, denominator);

        seizeTokens = mul_ScalarTruncate(ratio, actualRepayAmount);

        return (uint(Error.NO_ERROR), seizeTokens);
    }

    function getAccountLiquidity(address account, bool isProtectedCall) external view returns (uint, uint, uint) {
        (Error err, uint liquidity, uint shortfall) = getHypotheticalAccountLiquidityInternal(account, DToken(0), 0, 0, isProtectedCall);
        return (uint(err), liquidity, shortfall);
    }

    function redeemVerify(uint redeemAmount, uint redeemTokens) external {
        if (redeemTokens == 0 && redeemAmount > 0) {
            revert("redeemTokens zero");
        }
    }

    function getHypotheticalAccountLiquidityInternal(
        address account,
        DToken dTokenModify,
        uint redeemTokens,
        uint borrowAmount,
        bool isProtectedCall
        ) internal view returns (Error, uint, uint) {

        AccountLiquidityLocalVars memory vars;
        uint oErr;

        DToken[] memory assets = accountAssets[account];  
        
        for (uint i = 0; i < assets.length; i++) {
            DToken asset = assets[i];

            (oErr, vars.dTokenBalance, vars.borrowBalance, vars.exchangeRateMantissa) = asset.getAccountSnapshot(account); 

            require(oErr == 0, 'E82');
            vars.collateralFactor = Exp({mantissa: markets[address(asset)].collateralFactorMantissa});
            vars.exchangeRate = Exp({mantissa: vars.exchangeRateMantissa});

            vars.oraclePriceMantissa = priceOracle.getUnderlyingPrice(asset.underlyingSymbol());

            require(vars.oraclePriceMantissa != 0, 'E94');

            vars.oraclePrice = Exp({mantissa: vars.oraclePriceMantissa});
            vars.tokensToDenom = mul_(mul_(vars.collateralFactor, vars.exchangeRate), vars.oraclePrice);
            vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(vars.oraclePrice, vars.borrowBalance, vars.sumBorrowPlusEffects);

            if (isProtectedCall && protectedAssets[address(asset)]) {
                continue;
            }

            vars.sumCollateral = mul_ScalarTruncateAddUInt(vars.tokensToDenom, vars.dTokenBalance, vars.sumCollateral);

            if (asset == dTokenModify) {
                vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(vars.tokensToDenom, redeemTokens, vars.sumBorrowPlusEffects);
                vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(vars.oraclePrice, borrowAmount, vars.sumBorrowPlusEffects);
            }
        }

        if (vars.sumCollateral > vars.sumBorrowPlusEffects) {
            return (Error.NO_ERROR, vars.sumCollateral - vars.sumBorrowPlusEffects, 0);
        } else {
            return (Error.NO_ERROR, 0, vars.sumBorrowPlusEffects - vars.sumCollateral);
        }
    }

    function _setCloseFactor(uint newCloseFactorMantissa) external returns (uint) {
    	require(msg.sender == admin, 'E1');

        uint oldCloseFactorMantissa = closeFactorMantissa;
        closeFactorMantissa = newCloseFactorMantissa;
        emit NewCloseFactor(oldCloseFactorMantissa, closeFactorMantissa);

        return uint(Error.NO_ERROR);
    }

    function _setCollateralFactor(DToken dToken, uint newCollateralFactorMantissa) external returns (uint) {
        require(msg.sender == admin, 'E1');

        Market storage market = markets[address(dToken)];
        if (!market.isListed) {
            return fail(Error.MARKET_NOT_LISTED, FailureInfo.SET_COLLATERAL_FACTOR_NO_EXISTS);
        }

        Exp memory newCollateralFactorExp = Exp({mantissa: newCollateralFactorMantissa});

        Exp memory highLimit = Exp({mantissa: collateralFactorMaxMantissa});
        if (lessThanExp(highLimit, newCollateralFactorExp)) {
            return fail(Error.INVALID_COLLATERAL_FACTOR, FailureInfo.SET_COLLATERAL_FACTOR_VALIDATION);
        }

        if (newCollateralFactorMantissa != 0 && priceOracle.getUnderlyingPrice(dToken.underlyingSymbol()) == 0) {
            return fail(Error.PRICE_ERROR, FailureInfo.SET_COLLATERAL_FACTOR_WITHOUT_PRICE);
        }

        uint oldCollateralFactorMantissa = market.collateralFactorMantissa;
        market.collateralFactorMantissa = newCollateralFactorMantissa;

        emit NewCollateralFactor(dToken, oldCollateralFactorMantissa, newCollateralFactorMantissa);

        return uint(Error.NO_ERROR);
    }

    // DONKEY TOKEN $_$ //
    function setDonkeySpeedInternal(DToken dToken, uint donkeySpeed) internal {
        uint currentDonkeySpeed = donkeySpeeds[address(dToken)];
        if (currentDonkeySpeed != 0) {
            Exp memory borrowIndex = Exp({mantissa: dToken.borrowIndex()});
            updateDonkeySupplyIndex(address(dToken));
            updateDonkeyBorrowIndex(address(dToken), borrowIndex);
        } else if (donkeySpeed != 0) {
            Market storage market = markets[address(dToken)];
            require(market.isListed, 'E86');

            if (donkeySupplyState[address(dToken)].index == 0 && donkeySupplyState[address(dToken)].block == 0) {
                donkeySupplyState[address(dToken)] = DonkeyMarketState({
                    index: donkeyInitialIndex,
                    block: safe32(getBlockNumber(), "block number exceeds 32 bits")
                });
            }

            if (donkeyBorrowState[address(dToken)].index == 0 && donkeyBorrowState[address(dToken)].block == 0) {
                donkeyBorrowState[address(dToken)] = DonkeyMarketState({
                    index: donkeyInitialIndex,
                    block: safe32(getBlockNumber(), "block number exceeds 32 bits")
                });
            }
        }

        if (currentDonkeySpeed != donkeySpeed) {
            donkeySpeeds[address(dToken)] = donkeySpeed;
        }
    }

    function updateDonkeySupplyIndex(address dToken) internal {
        DonkeyMarketState storage supplyState = donkeySupplyState[dToken];

        uint supplySpeed = donkeySpeeds[dToken];
        uint blockNumber = getBlockNumber();
        uint deltaBlocks = sub_(blockNumber, uint(supplyState.block));

        if (deltaBlocks > 0 && supplySpeed > 0) {

            uint supplyTokens = DToken(dToken).totalSupply();
            uint donkeyAccrued = mul_(deltaBlocks, supplySpeed);

            Double memory ratio = supplyTokens > 0 ? fraction(donkeyAccrued, supplyTokens) : Double({mantissa: 0});
            Double memory index = add_(Double({mantissa: supplyState.index}), ratio);

            donkeySupplyState[dToken] = DonkeyMarketState({
                index: safe224(index.mantissa, "new index exceeds 224 bits"),
                block: safe32(blockNumber, "block number exceeds 32 bits")
            });

        } else if (deltaBlocks > 0) {
            supplyState.block = safe32(blockNumber, "block number exceeds 32 bits");
        }
    }

    function updateDonkeyBorrowIndex(address dToken, Exp memory marketBorrowIndex) internal {
        DonkeyMarketState storage borrowState = donkeyBorrowState[dToken];

        uint borrowSpeed = donkeySpeeds[dToken];
        uint blockNumber = getBlockNumber();
        uint deltaBlocks = sub_(blockNumber, uint(borrowState.block));

        if (deltaBlocks > 0 && borrowSpeed > 0) {

            uint borrowAmount = div_(DToken(dToken).totalBorrows(), marketBorrowIndex);
            uint donkeyAccrued = mul_(deltaBlocks, borrowSpeed);

            Double memory ratio = borrowAmount > 0 ? fraction(donkeyAccrued, borrowAmount) : Double({mantissa: 0});
            Double memory index = add_(Double({mantissa: borrowState.index}), ratio);

            donkeyBorrowState[dToken] = DonkeyMarketState({
                index: safe224(index.mantissa, "new index exceeds 224 bits"),
                block: safe32(blockNumber, "block number exceeds 32 bits")
            });
        } else if (deltaBlocks > 0) {
            borrowState.block = safe32(blockNumber, "block number exceeds 32 bits");
        }
    }

    function distributeSupplierDonkey(address dToken, address supplier) internal {
        DonkeyMarketState storage supplyState = donkeySupplyState[dToken];

        Double memory supplyIndex = Double({mantissa: supplyState.index});
        Double memory supplierIndex = Double({mantissa: donkeySupplierIndex[dToken][supplier]});

        donkeySupplierIndex[dToken][supplier] = supplyIndex.mantissa;

        if (supplierIndex.mantissa == 0 && supplyIndex.mantissa > 0) {
            supplierIndex.mantissa = donkeyInitialIndex;
        }

        Double memory deltaIndex = sub_(supplyIndex, supplierIndex);

        uint supplierTokens = DToken(dToken).balanceOf(supplier);
        uint supplierDelta = mul_(supplierTokens, deltaIndex);
        uint supplierAccrued = add_(donkeyAccrued[supplier], supplierDelta);

        donkeyAccrued[supplier] = supplierAccrued;

        emit DistributeSupplierDonkey(DToken(dToken), supplier, supplierDelta, supplyIndex.mantissa);
    }

    function setDonkeyLockUp(uint lockupBlockNum) external returns (uint) {
        require(msg.sender == admin, 'E1');
        donkeyLockUpBlock = lockupBlockNum;
        return donkeyLockUpBlock;
    }

    function claimDonkey(address holder) public {
        require(block.number > donkeyLockUpBlock, 'E95');
        return claimDonkey(holder, allMarkets);
    }

    function claimDonkey(address holder, DToken[] memory dTokens) public {
        require(block.number > donkeyLockUpBlock, 'E95');
        address[] memory holders = new address[](1);
        holders[0] = holder;
        claimDonkey(holders, dTokens, true, true, false);
    }

    function claimDonkey(address[] memory holders, DToken[] memory dTokens, bool borrowers, bool suppliers, bool isMax) public { 

        if (isMax) {
            require(isStakingContract[msg.sender]);
        } else{
            require(block.number > donkeyLockUpBlock, 'E95');
        }

        for (uint i = 0; i < dTokens.length; i++) {
            DToken dToken = dTokens[i];
            require(markets[address(dToken)].isListed, 'E86');
            if (borrowers) {
                Exp memory borrowIndex = Exp({mantissa: dToken.borrowIndex()});
                updateDonkeyBorrowIndex(address(dToken), borrowIndex);
                for (uint j = 0; j < holders.length; j++) {
                    distributeBorrowerDonkey(address(dToken), holders[j], borrowIndex);
                    donkeyAccrued[holders[j]] = grantDonkeyInternal(holders[j], donkeyAccrued[holders[j]]);
                }
            }
            if (suppliers) {
                updateDonkeySupplyIndex(address(dToken));
                for (uint j = 0; j < holders.length; j++) {
                    distributeSupplierDonkey(address(dToken), holders[j]);
                    donkeyAccrued[holders[j]] = grantDonkeyInternal(holders[j], donkeyAccrued[holders[j]]);
                }
            }
        }
    }

    function distributeBorrowerDonkey(address dToken, address borrower, Exp memory marketBorrowIndex) internal {
        DonkeyMarketState storage borrowState = donkeyBorrowState[dToken];

        Double memory borrowIndex = Double({mantissa: borrowState.index});
        Double memory borrowerIndex = Double({mantissa: donkeyBorrowerIndex[dToken][borrower]});

        donkeyBorrowerIndex[dToken][borrower] = borrowIndex.mantissa;

        if (borrowerIndex.mantissa > 0) {
            Double memory deltaIndex = sub_(borrowIndex, borrowerIndex);

            uint borrowerAmount = div_(DToken(dToken).borrowBalanceStored(borrower), marketBorrowIndex);
            uint borrowerDelta = mul_(borrowerAmount, deltaIndex);
            uint borrowerAccrued = add_(donkeyAccrued[borrower], borrowerDelta);
            
            donkeyAccrued[borrower] = borrowerAccrued;

            emit DistributeBorrowerDonkey(DToken(dToken), borrower, borrowerDelta, borrowIndex.mantissa);
        }
    }

    function grantDonkeyInternal(address user, uint amount) internal returns (uint) {
        Donkey donkey = Donkey(getDonkeyAddress());
        uint donkeyRemaining = donkey.balanceOf(address(this));
        if (amount > 0 && amount <= donkeyRemaining) {
            donkey.transfer(user, amount);
            return 0;
        }
        return amount;
    }

    // Donkey Admin $_$  //

    function _grantDonkey(address recipient, uint amount) public {
        require(msg.sender == admin, 'E1');
        uint amountLeft = grantDonkeyInternal(recipient, amount);
        require(amountLeft == 0, 'E96');
    }

    function _setDonkeySpeed(DToken[] memory dTokens, uint[] memory donkeySpeeds) public {
        require(msg.sender == admin, 'E1');
        uint len = dTokens.length;
        for (uint i = 0 ; i < len ; i+=1) {
            setDonkeySpeedInternal(dTokens[i], donkeySpeeds[i]);
        }
    }

    function getDonkeyAddress() view public returns (address) {
        return DONKEY_ADDRESS;
    }

    function getBlockNumber() public view returns (uint) {
        return block.number;    
    }

    function getAccountAssets(address owner) external view returns (DToken[] memory) {
        return accountAssets[owner];
    }

    function getAccountLiquidityInternal(address account, bool isProtectedCall) internal view returns (Error, uint, uint) {
        return getHypotheticalAccountLiquidityInternal(account, DToken(0), 0, 0, isProtectedCall);
    }

    function liquidateBorrowAllowed(
        address dTokenBorrowed,
        address dTokenCollateral,
        address borrower,
        address liquidator,
        uint repayAmount
        ) external returns (uint) {
        if (!markets[dTokenBorrowed].isListed || !markets[dTokenCollateral].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        uint enteredMarket = enterMarkets(dTokenCollateral, liquidator);
        require(enteredMarket == uint(Error.NO_ERROR), 'E89');

        require(!oracleGuardianPaused[dTokenCollateral] || !oracleGuardianPaused[dTokenBorrowed], "E97");

        (Error err, , uint shortfall) = getAccountLiquidityInternal(borrower, false);
        if (err != Error.NO_ERROR) {
            return uint(err);
        }

        if (shortfall == 0) {
            return uint(Error.INSUFFICIENT_SHORTFALL);
        }

        uint borrowBalance = DToken(dTokenBorrowed).borrowBalanceStored(borrower);
        uint maxClose = mul_ScalarTruncate(Exp({mantissa: closeFactorMantissa}), borrowBalance);
        if (repayAmount > maxClose) {
            return uint(Error.TOO_MUCH_REPAY);
        }
        return uint(Error.NO_ERROR);
    }

    function _setLiquidationIncentive(DToken[] calldata dTokens, uint[] calldata newLiquidationIncentiveMantissas) external returns (uint) {
        require(msg.sender == admin, 'E1');

        uint len = dTokens.length;
        for (uint i = 0 ; i < len ; i+=1) {
            liquidationIncentiveMantissa[address(dTokens[i])] = newLiquidationIncentiveMantissas[i];
        }

        return uint(Error.NO_ERROR);
    }

    /*
    function _setPriceOracle(PriceOracle newOracle) public returns (uint) {
        require(msg.sender == admin, 'E1');
        priceOracle = newOracle;

        emit NewPriceOracle(newOracle);

        return uint(Error.NO_ERROR);
    }
    */

    function getAllMarkets() external view returns (DToken[] memory) {
        return allMarkets;
    }

    function getCurrentMyDonkey(address account) external view returns (uint) {
        DToken[] memory assets = accountAssets[account];
        uint len = assets.length;
        uint total = donkeyAccrued[account];

        for (uint i=0; i < len; i+=1) {
            {

            DonkeyMarketState memory supplyState = donkeySupplyState[address(assets[i])];
            Double memory supplyIndex = Double({mantissa: supplyState.index});
            Double memory supplierIndex = Double({mantissa: donkeySupplierIndex[address(assets[i])][account]});

            if (supplierIndex.mantissa == 0 && supplyIndex.mantissa > 0) {
                supplierIndex.mantissa = donkeyInitialIndex;
            }

            Double memory deltaSupplyIndex = sub_(supplyIndex, supplierIndex);

            uint supplierTokens = DToken(assets[i]).balanceOf(account);
            uint supplierDelta = mul_(supplierTokens, deltaSupplyIndex);
            uint supplierAccrued = add_(total, supplierDelta);
            total = supplierAccrued;
            }

            {
            DonkeyMarketState memory borrowState = donkeyBorrowState[address(assets[i])];
            Double memory borrowIndex = Double({mantissa: borrowState.index});
            Double memory borrowerIndex = Double({mantissa: donkeyBorrowerIndex[address(assets[i])][account]});

            Double memory deltaBorrowIndex = sub_(borrowIndex, borrowerIndex);

            Exp memory marketBorrowIndex = Exp({mantissa: assets[i].borrowIndex()});
            uint borrowerAmount = div_(DToken(assets[i]).borrowBalanceStored(account), marketBorrowIndex);
            uint borrowerDelta = mul_(borrowerAmount, deltaBorrowIndex);
            uint borrowerAccrued = add_(total, borrowerDelta);
            total = borrowerAccrued;
            }
        }
        return total;
    }

    function claimDonkeyBehalfOf(address account, bool isMax) external returns (bool) {
        require(isStakingContract[msg.sender], "E1");
        address[] memory holders = new address[](1);
        holders[0] = account;
        uint len = allMarkets.length;
        DToken[] memory tempDTokens = new DToken[](len);
        uint count = 0;
        for (uint i = 0 ; i < len ; i += 1) {
            if (donkeySupplierIndex[address(allMarkets[i])][account] > 0 || donkeyBorrowerIndex[address(allMarkets[i])][account] > 0) {
                tempDTokens[count] = allMarkets[i];
                count += 1;
            }
        }

        if (count <= 0) {
            return false;
        }

        DToken[] memory dTokens = new DToken[](count);
        len = dTokens.length;
        for (uint j = 0 ; j < len ; j += 1) {
            dTokens[j] = tempDTokens[j];
        }
        claimDonkey(holders, dTokens, true, true, isMax);
        return true;
    }

    function setIsStakingContract(address[] calldata stakingAddressList, bool state) external {
        require(msg.sender == admin, "E1");
        uint len = stakingAddressList.length;
        for(uint i = 0; i < len; i += 1){
            isStakingContract[stakingAddressList[i]] = state;
        }
    }

    function getLiquidationIncentiveOf(address dToken) external view returns (uint) {
      return liquidationIncentiveMantissa[dToken];
    }
}
