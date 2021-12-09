// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.5.6;
pragma experimental ABIEncoderV2;

import "./StakingInterface.sol";
import "../common/Exponential.sol";
import "../common/upgradeable/Initializable.sol";

/**
 * @title Donkey's Staking Contract
 * @notice Staking Contract for DON Tokens
 * @author Donkey
 */

contract Staking is Initializable, StakingInterface, Exponential {
    function initialize(address donkeyAddress_, uint lockupTerm_, uint totalInterestLimitAmount_, uint interestRate_, Controller controller_) public initializer {

        require(controller_.isController());

        admin = msg.sender;
        donkeyAddress = donkeyAddress_;
        controller = controller_;
        
        stakingMetaData.lockupTerm = lockupTerm_;
        stakingMetaData.totalInterestLimitAmount = totalInterestLimitAmount_;
        stakingMetaData.interestRate = interestRate_;


        _notEntered = true;
    }

    struct MintLocalVars {
        uint donkeyBalance;
        uint actualMintAmount;
        uint totalExpectedInterest;
        bool claimResult;
        address payable account;
    }
    
    function mint(uint mintAmount) external nonReentrant returns (uint) {
        require(mintAmount > 0, "E101");

        MintLocalVars memory vars;
        
        vars.account = msg.sender;

        require(stakingProductOf[vars.account][block.timestamp].principal == 0, "E102");

        // totalExpectedInterest = (totalPrincipalAmount + mintAmount) * interestRate + totalPaidInterestAmount
        vars.totalExpectedInterest = add_(_expectedInterest(add_(stakingMetaData.totalPrincipalAmount, mintAmount)), stakingMetaData.totalPaidInterestAmount);
        require(vars.totalExpectedInterest <= stakingMetaData.totalInterestLimitAmount, "E103");

        IERC20 donkey = IERC20(donkeyAddress);
        vars.donkeyBalance = donkey.balanceOf(vars.account);

        if (mintAmount > vars.donkeyBalance) {
            // reference : https://github.com/donkey-fund/staking/blob/main/readme.md/#Notice
            vars.claimResult = controller.claimDonkeyBehalfOf(vars.account, false);
            require(vars.claimResult, "E105");
            require(mintAmount <= currentTotalDonBalanceOf(vars.account), "E104");
        } 

        vars.actualMintAmount = _doTransferIn(vars.account, mintAmount);
        // totalPrincipalAmount = totalPrincipalAmount + actualMintAmount
        stakingMetaData.totalPrincipalAmount = add_(stakingMetaData.totalPrincipalAmount, vars.actualMintAmount);
        _createStakingProductTo(vars.account, vars.actualMintAmount);

        emit Mint(vars.account, vars.actualMintAmount);

        return vars.actualMintAmount;
    }

    function mintMax() external nonReentrant returns (uint) {
        MintLocalVars memory vars;
        
        vars.account = msg.sender;

        // reference : https://github.com/donkey-fund/staking/blob/main/readme.md/#Notice
        vars.claimResult = controller.claimDonkeyBehalfOf(vars.account, true);
        require(vars.claimResult, "E105");

        uint mintAmount = currentTotalDonBalanceOf(vars.account);

        require(stakingProductOf[vars.account][block.timestamp].principal == 0, "E102");

        // totalExpectedInterest = (totalPrincipalAmount + mintAmount) * interestRate + totalPaidInterestAmount
        vars.totalExpectedInterest = add_(_expectedInterest(add_(stakingMetaData.totalPrincipalAmount, mintAmount)), stakingMetaData.totalPaidInterestAmount);
        require(vars.totalExpectedInterest <= stakingMetaData.totalInterestLimitAmount, "E103");

        // IERC20 donkey = IERC20(donkeyAddress);
        // vars.donkeyBalance = donkey.balanceOf(vars.account);

        vars.actualMintAmount = _doTransferIn(vars.account, mintAmount);
        // totalPrincipalAmount = totalPrincipalAmount + actualMintAmount
        stakingMetaData.totalPrincipalAmount = add_(stakingMetaData.totalPrincipalAmount, vars.actualMintAmount);
        _createStakingProductTo(vars.account, vars.actualMintAmount);

        emit Mint(vars.account, vars.actualMintAmount);

        return vars.actualMintAmount;
    }
    // redeem principal with interest after lockupTerm
    function redeem(uint registeredTimestamp) external nonReentrant returns (uint) {
        address payable account = msg.sender;

        require(stakingProductOf[account][registeredTimestamp].principal > 0, "E106");
        require(stakingProductOf[account][registeredTimestamp].releaseTime <= block.timestamp, "E107");

        uint totalPaidInterestAmountNew = add_(stakingMetaData.totalPaidInterestAmount, _expectedInterest(stakingProductOf[account][registeredTimestamp].principal));
        require(totalPaidInterestAmountNew <= stakingMetaData.totalInterestLimitAmount, "E108");

        uint actualRedeemAmount = _doTransferOut(account, _expectedPrincipalAndInterest(stakingProductOf[account][registeredTimestamp].principal));
        stakingMetaData.totalPrincipalAmount = sub_(stakingMetaData.totalPrincipalAmount, stakingProductOf[account][registeredTimestamp].principal);

        // totalPaidInterestAmount = totalPaidInterestAmount + (principal * interestRate)
        stakingMetaData.totalPaidInterestAmount = totalPaidInterestAmountNew;
        _deleteStakingProductFrom(account, registeredTimestamp);

        emit Redeem(account, actualRedeemAmount);

        return actualRedeemAmount;
    }

    // redeem principal ONLY before lockupTerm
    function redeemPrincipal(uint registeredTimestamp) external nonReentrant returns (uint) {
        require(block.number >= 13329882);
        address payable account = msg.sender;
        require(stakingProductOf[account][registeredTimestamp].principal > 0, "E106");
        uint actualRedeemAmount = _doTransferOut(account, stakingProductOf[account][registeredTimestamp].principal);
        // totalPrincipalAmount = totalPrincipalAmount - principal
        stakingMetaData.totalPrincipalAmount = sub_(stakingMetaData.totalPrincipalAmount, stakingProductOf[account][registeredTimestamp].principal);
        _deleteStakingProductFrom(account, registeredTimestamp);

        emit RedeemPrincipal(account, actualRedeemAmount);

        return actualRedeemAmount;
    }

    function updateStakingStandard(uint newLockupTerm, uint newLimitAmount, uint newInterestRate) external {
        require(admin == msg.sender, "E1");

        require(newLockupTerm > 0);
        require(newLimitAmount > 0);
        require(newInterestRate > 0);
        stakingMetaData.lockupTerm = newLockupTerm;
        stakingMetaData.totalInterestLimitAmount = newLimitAmount;
        stakingMetaData.interestRate = newInterestRate;

        emit UpdateStakingStandard(newLockupTerm, newLimitAmount, newInterestRate);
    }


    // return (totalPaidInterestAmount + (totalPrincipalAmount * interestRate)) / totalInterestLimitAmount
    function currentUsedRateOfInterestLimit() external view returns (uint) {
        return div_(mul_(add_(stakingMetaData.totalPaidInterestAmount, _expectedInterest(stakingMetaData.totalPrincipalAmount)), 10 ** 18), stakingMetaData.totalInterestLimitAmount);
    }

    function stakingProductsOf(address account) external view returns (StakingProductView[] memory) {
        uint[] memory timestampKeys = allStakingProductsTimestampOf[account];
        uint len = timestampKeys.length;

        StakingProductView[] memory stakingProductViewList = new StakingProductView[](len);

        for (uint i = 0; i < len; i += 1){
            StakingProductView memory stakingProductView;

            stakingProductView.startTime = timestampKeys[i];
            stakingProductView.releaseTime = stakingProductOf[account][timestampKeys[i]].releaseTime;
            stakingProductView.principal = stakingProductOf[account][timestampKeys[i]].principal;
            stakingProductView.lockupTerm = stakingMetaData.lockupTerm;
            stakingProductView.interestRate = stakingMetaData.interestRate;
            
            stakingProductViewList[i] = stakingProductView;
        }

        return stakingProductViewList;
    }

    function setController(Controller newController) external {
        require(admin == msg.sender, "E1");
        require(newController.isController());

        Controller oldController = controller;
        controller = newController;

        emit UpdateController(oldController, newController);
    }

    function setAdmin(address newAdmin) external {
        require(admin == msg.sender, "E1");
        address oldAdmin = admin;
        admin = newAdmin;

        emit UpdateAdmin(oldAdmin, newAdmin);
    }

    function currentTotalDonBalanceOf(address account) public view returns (uint) {
        IERC20 donkey = IERC20(donkeyAddress);
        return add_(donkey.balanceOf(account), controller.donkeyAccrued(account));
    }

    function _createStakingProductTo(address account, uint principal) internal {
        allStakingProductsTimestampOf[account].push(block.timestamp);
        stakingProductOf[account][block.timestamp].principal = principal;
        stakingProductOf[account][block.timestamp].releaseTime = add_(block.timestamp, stakingMetaData.lockupTerm);
    }

    function _deleteStakingProductFrom(address account, uint registeredTimestamp) internal {
        uint len = allStakingProductsTimestampOf[account].length;

        require(len > 0);

        uint idx = len;

        for (uint i = 0; i < len; i += 1) {
            if (registeredTimestamp == allStakingProductsTimestampOf[account][i]) {
                idx = i;
                break;
            }
        }
        // handle invalid idx value
        require(idx < len);

        allStakingProductsTimestampOf[account][idx] = allStakingProductsTimestampOf[account][len - 1];
        delete allStakingProductsTimestampOf[account][len - 1];
        allStakingProductsTimestampOf[account].length--;

        delete stakingProductOf[account][registeredTimestamp];
    }

    function _expectedInterest(uint amount) internal view returns (uint) {
        return mul_(amount, Exp({mantissa: stakingMetaData.interestRate}));
    }

    function _expectedPrincipalAndInterest(uint amount) internal view returns (uint) {
        return mul_ScalarTruncateAddUInt(Exp({ mantissa: stakingMetaData.interestRate }), amount, amount);
    }

    // reference : https://github.com/compound-finance/compound-protocol/blob/master/contracts/CErc20.sol
    function _doTransferIn(address sender, uint amount) internal returns (uint) {
        IERC20 token = IERC20(donkeyAddress);

        uint balanceBeforeTransfer = IERC20(donkeyAddress).balanceOf(address(this));
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

        uint balanceAfterTransfer = IERC20(donkeyAddress).balanceOf(address(this));
        require(balanceAfterTransfer >= balanceBeforeTransfer , "E80");

        return balanceAfterTransfer - balanceBeforeTransfer;
    }

    // reference : https://github.com/compound-finance/compound-protocol/blob/master/contracts/CErc20.sol
    function _doTransferOut(address payable recipient, uint amount) internal returns (uint) {
        IERC20 token = IERC20(donkeyAddress);
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

    // reference : https://github.com/compound-finance/compound-protocol/blob/master/contracts/CToken.sol
    modifier nonReentrant() {
        require(_notEntered, "E67");
        _notEntered = false;
        _;
        _notEntered = true; // get a gas-refund post-Istanbul
    }
}