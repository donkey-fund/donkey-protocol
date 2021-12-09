// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.5.6;
pragma experimental ABIEncoderV2;

import "../common/Exponential.sol";
import "../common/upgradeable/Initializable.sol";

import "./VDON.sol";
import "./VDONNonInterestStakingInterface.sol";
import "../lending/IERC20.sol";

/**
 * @title Donkey's VDON Staking Contract for governance
 * @notice VDON Staking Contract for governance
 * @author Donkey
 */

contract VDONNonInterestStaking is Initializable, VDONNonInterestStakingInterface, Exponential {
    function initialize(
        address DONAddress_, 
        address VDONAddress_ 
        ) public initializer {

        admin = msg.sender;
        DONAddress = DONAddress_;
        VDONAddress = VDONAddress_;

        _notEntered = true;
    }

    struct MintLocalVars {
        uint DONBalance;
        uint actualMintAmount;
        bool claimResult;
        address payable account;
    }
    
    function mint(uint productInfoId, uint mintAmount) external nonReentrant returns (uint) {
        require(mintAmount > 0, "E101");

        MintLocalVars memory vars;
        
        vars.account = msg.sender;

        vars.DONBalance = IERC20(DONAddress).balanceOf(vars.account);
        require(vars.DONBalance >= mintAmount, "E104");

        ProductInfo storage productInfo = getProductInfoById[productInfoId];
        require(productInfo.isActivate, "E109");

        vars.actualMintAmount = _doTransferIn(vars.account, mintAmount, DONAddress);
        // totalPrincipalAmount = totalPrincipalAmount + actualMintAmount
        productInfo.totalPrincipalAmount = add_(productInfo.totalPrincipalAmount, vars.actualMintAmount);
        
        _createProductWith(productInfoId, vars.account, vars.actualMintAmount);

        VDON(VDONAddress).mint(vars.account, mul_(productInfo.VDONExchangeRate, vars.actualMintAmount));
        emit Mint(vars.account, vars.actualMintAmount);

        return vars.actualMintAmount;
    }

    struct RedeemLocalVars {
        uint productInfoId;
        uint accountPrincipal;
        uint DONRedeemAmount;
        address payable account;
    }

    // redeem principal with interest after lockupTerm
    function redeem(uint redeemProductId) external nonReentrant {
        RedeemLocalVars memory vars;

        vars.account = msg.sender;

        require(productOf[vars.account][redeemProductId].principal > 0, "E106");
        require(productOf[vars.account][redeemProductId].releaseTime <= block.timestamp, "E107");

        vars.productInfoId = productOf[vars.account][redeemProductId].productInfoId;
        vars.accountPrincipal = productOf[vars.account][redeemProductId].principal;

        ProductInfo storage productInfo = getProductInfoById[vars.productInfoId];

        vars.DONRedeemAmount = _doTransferOut(vars.account, vars.accountPrincipal, DONAddress);

        productInfo.totalPrincipalAmount = sub_(productInfo.totalPrincipalAmount, vars.accountPrincipal);

        VDON(VDONAddress).burn(vars.account, mul_(productInfo.VDONExchangeRate, vars.accountPrincipal));

        _deleteProductFrom(vars.account, redeemProductId);

        emit Redeem(vars.account, vars.DONRedeemAmount);
    }

    function redeemAdmin(address payable minter, uint redeemProductId) external nonReentrant {
        require(msg.sender == admin);
        RedeemLocalVars memory vars;

        vars.account = minter;
        require(productOf[vars.account][redeemProductId].principal > 0, "E106");

        vars.productInfoId = productOf[vars.account][redeemProductId].productInfoId;
        vars.accountPrincipal = productOf[vars.account][redeemProductId].principal;

        ProductInfo storage productInfo = getProductInfoById[vars.productInfoId];

        vars.DONRedeemAmount = _doTransferOut(vars.account, vars.accountPrincipal, DONAddress);

        productInfo.totalPrincipalAmount = sub_(productInfo.totalPrincipalAmount, vars.accountPrincipal);

        VDON(VDONAddress).burn(vars.account, mul_(productInfo.VDONExchangeRate, vars.accountPrincipal));

        _deleteProductFrom(vars.account, redeemProductId);

        emit Redeem(vars.account, vars.DONRedeemAmount);        
    }

    function createProductInfo(
        bool isActivate_,
        uint lockupTerm_,
        uint VDONExchangeRate_
    ) external returns (ProductInfo memory) {
        require(msg.sender == admin);
        ProductInfo storage productInfo = getProductInfoById[freshProductInfoId];
        productInfo.lockupTerm = lockupTerm_;
        productInfo.VDONExchangeRate = VDONExchangeRate_;

        productInfo.isActivate = isActivate_;

        getProductInfoById[freshProductInfoId] = productInfo;
        freshProductInfoId += 1;

        return productInfo;
    }

    function updateProductInfo(
        bool isActivate_,
        uint productInfoId,
        uint newLockupTerm,
        uint newVDONExchangeRate
    ) external returns (ProductInfo memory) {
        require(msg.sender == admin, "E1");

        require(newLockupTerm > 0 &&
                newVDONExchangeRate > 0);

        ProductInfo storage productInfo = getProductInfoById[productInfoId];
        productInfo.lockupTerm = newLockupTerm;
        productInfo.VDONExchangeRate = newVDONExchangeRate;

        productInfo.isActivate = isActivate_;

        return productInfo;
    }


    function setAdmin(address newAdmin) external {
        require(admin == msg.sender, "E1");
        address oldAdmin = admin;
        admin = newAdmin;

        emit UpdateAdmin(oldAdmin, newAdmin);
    }

    function enteredProductOf(address account) external view returns (ProductView[] memory) {
        uint[] memory productIdList = allProductsIdOf[account];
        uint len = productIdList.length;

        ProductView[] memory stakingProductViewList = new ProductView[](len);

        for (uint i = 0; i < len; i += 1){
            uint productId = productIdList[i];
            ProductView memory stakingProductView;
            
            EnteredProduct memory product = productOf[account][productId];
            ProductInfo memory productInfo = getProductInfoById[product.productInfoId];

            stakingProductView.startTime = product.releaseTime - productInfo.lockupTerm;
            stakingProductView.releaseTime = product.releaseTime;
            stakingProductView.principal = product.principal;
            stakingProductView.lockupTerm = productInfo.lockupTerm;
            stakingProductView.vDONExchangeRate = productInfo.VDONExchangeRate;
            stakingProductView.productInfoId = product.productInfoId;
            stakingProductView.productId = productId;
            
            stakingProductViewList[i] = stakingProductView;
        }

        return stakingProductViewList;
    }

    function productInfoList() external view returns(ProductInfoView[] memory) {
        ProductInfoView[] memory productInfoViewList = new ProductInfoView[](freshProductInfoId);
        for(uint i = 0; i < freshProductInfoId; i += 1){
            ProductInfo memory productInfo = getProductInfoById[i];

            productInfoViewList[i].isActivate = productInfo.isActivate; 
            productInfoViewList[i].lockupTerm = productInfo.lockupTerm;
            productInfoViewList[i].VDONExchangeRate = productInfo.VDONExchangeRate;
            productInfoViewList[i].totalPrincipalAmount = productInfo.totalPrincipalAmount;
            productInfoViewList[i].productInfoId = i;
        }
        return productInfoViewList;
    }


    function _createProductWith(uint productInfoId, address account, uint principal) internal {
        ProductInfo memory productInfo = getProductInfoById[productInfoId];

        allProductsIdOf[account].push(freshProductId);

        productOf[account][freshProductId].productInfoId = productInfoId;
        productOf[account][freshProductId].releaseTime = add_(block.timestamp, productInfo.lockupTerm);
        productOf[account][freshProductId].principal = principal;

        freshProductId += 1;
    }

    function _deleteProductFrom(address account, uint targetProductId) internal {
        uint len = allProductsIdOf[account].length;

        require(len > 0, "E112");

        uint idx = len;

        for (uint i = 0; i < len; i += 1) {
            if (targetProductId == allProductsIdOf[account][i]) {
                idx = i;
                break;
            }
        }

        // handle invalid idx value
        require(idx < len, "E113");

        allProductsIdOf[account][idx] = allProductsIdOf[account][len - 1];
        delete allProductsIdOf[account][len - 1];
        allProductsIdOf[account].length--;

        delete productOf[account][targetProductId];
    }

    // reference : https://github.com/compound-finance/compound-protocol/blob/master/contracts/CErc20.sol
    function _doTransferIn(address sender, uint amount, address tokenAddress) internal returns (uint) {
        IERC20 token = IERC20(tokenAddress);

        uint balanceBeforeTransfer = IERC20(tokenAddress).balanceOf(address(this));
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

        uint balanceAfterTransfer = IERC20(DONAddress).balanceOf(address(this));
        require(balanceAfterTransfer >= balanceBeforeTransfer , "E80");

        return balanceAfterTransfer - balanceBeforeTransfer;
    }

    // reference : https://github.com/compound-finance/compound-protocol/blob/master/contracts/CErc20.sol
    function _doTransferOut(address payable recipient, uint amount, address tokenAddress) internal returns (uint) {
        IERC20 token = IERC20(tokenAddress);
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
