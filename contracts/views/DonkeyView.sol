pragma solidity ^0.5.6;
pragma experimental ABIEncoderV2;

import "../lending/DErc20.sol";
import "../lending/DToken.sol";
import "../lending/IERC20.sol";
import "../lending/Controller.sol";
import "../Donkey.sol";
import "../lending/InterestRateModel.sol";

contract DonkeyView is ControllerStorage {
  struct DTokenInfo {
    address underlyingAssetAddress;
    uint exchangeRateCurrent;
    uint underlyingDecimals;
    uint poolBalance;
    string underlyingSymbol;
    string symbol;
    address contractAddress;
    uint supplyRatePerBlock;
    uint borrowRatePerBlock;
    uint totalSupply;
    uint totalBorrow;
    uint collateralFactor;
    uint donkeySpeed;
    uint totalReserves;
    uint cash;
    uint donkeySupplyBlock;
    uint donkeyBorrowBlock;
    uint reserveFactorMantissa;
    uint multiplierPerBlock;
    uint kink;
    uint baseRatePerBlock;
    uint jumpMultiplierPerBlock;
  }

  struct AccountInfo {
    uint mySuppliedBalance;
    uint myBorrowedBalance;
    uint mySupplyPrincipalBalance;
    uint myBorrowPrincipalBalance;
    uint myRealTokenBalance;
    uint donkeyBorrowerIndex;
    uint donkeySupplierIndex;
  }
  
  struct DTokenMetaData {
    DTokenInfo dTokenInfo;
    AccountInfo accountInfo;
  }

  Controller public controller;
  // dKLAY or dETH depends on network
  string public mainDTokenSymbol = "dETH";

  address public admin;

  constructor (Controller controller_) public {
    controller = controller_;
    admin = msg.sender;
  }

  function setController(Controller newController_) external {
    require(msg.sender == admin);
    controller = newController_;
  }

  // returns DTokenInfo
  function getDTokenInfo(DToken dToken) public returns (DTokenInfo memory) {
    address underlyingAssetAddress;
    uint underlyingDecimals;
    bool isETH = compareStrings(dToken.symbol(), mainDTokenSymbol);
    DTokenInfo memory dTokenInfo;

    if (isETH) {
      underlyingAssetAddress = address(0);
      underlyingDecimals = 18;
    } else {
      DErc20 dErc20 = DErc20(address(dToken));
      underlyingAssetAddress = dErc20.underlying();
      underlyingDecimals = IERC20(dErc20.underlying()).decimals();
    }

    address contractAddress = address(dToken);

    dTokenInfo.underlyingAssetAddress = underlyingAssetAddress;
    dTokenInfo.underlyingDecimals = underlyingDecimals;
    dTokenInfo.contractAddress = contractAddress;
    dTokenInfo.poolBalance = isETH ? contractAddress.balance : IERC20(underlyingAssetAddress).balanceOf(contractAddress);
    dTokenInfo.underlyingSymbol = isETH ? "ETH" : IERC20(underlyingAssetAddress).symbol();
    dTokenInfo.symbol = dToken.symbol();
    dTokenInfo.supplyRatePerBlock = dToken.supplyRatePerBlock();
    dTokenInfo.borrowRatePerBlock = dToken.borrowRatePerBlock();
    dTokenInfo.totalSupply = dToken.totalSupply();
    dTokenInfo.totalBorrow = dToken.totalBorrows();
    (, dTokenInfo.collateralFactor, ) = controller.markets(contractAddress);
    dTokenInfo.donkeySpeed = controller.donkeySpeeds(contractAddress);
    dTokenInfo.totalReserves = dToken.totalReserves();
    dTokenInfo.cash = dToken.getCash();
    (, dTokenInfo.donkeySupplyBlock) = controller.donkeySupplyState(contractAddress);
    (, dTokenInfo.donkeyBorrowBlock) = controller.donkeyBorrowState(contractAddress);
    dTokenInfo.reserveFactorMantissa = dToken.reserveFactorMantissa();
    dTokenInfo.exchangeRateCurrent = dToken.exchangeRateCurrent();

    InterestRateModel interestRateModel = dToken.interestRateModel();

    dTokenInfo.multiplierPerBlock = interestRateModel.multiplierPerBlock();
    dTokenInfo.kink = interestRateModel.kink();
    dTokenInfo.baseRatePerBlock = interestRateModel.baseRatePerBlock();
    dTokenInfo.jumpMultiplierPerBlock = interestRateModel.jumpMultiplierPerBlock();

    return dTokenInfo;
  }

  // returns AccountInfo
  function getAccountInfo(DToken dToken, address payable account) public returns (AccountInfo memory) {
    AccountInfo memory accountInfo;

    address underlyingAssetAddress;
    address contractAddress = address(dToken);

    bool isETH = compareStrings(dToken.symbol(), mainDTokenSymbol); 
    if (isETH) {
      underlyingAssetAddress = address(0);
    } else {
      DErc20 dErc20 = DErc20(address(dToken));
      underlyingAssetAddress = dErc20.underlying();
    }

    accountInfo.mySuppliedBalance = dToken.balanceOfUnderlying(account);
    accountInfo.myBorrowedBalance = dToken.borrowBalanceStored(account);
    accountInfo.mySupplyPrincipalBalance = dToken.supplyPrincipal(account);
    accountInfo.myBorrowPrincipalBalance = dToken.borrowPrincipal(account);
    accountInfo.myRealTokenBalance = isETH ? account.balance : IERC20(underlyingAssetAddress).balanceOf(account); 
    accountInfo.donkeySupplierIndex = controller.donkeySupplierIndex(contractAddress, account);
    accountInfo.donkeyBorrowerIndex = controller.donkeyBorrowerIndex(contractAddress, account);

    return accountInfo;
  }

  function dTokenMetaDataList() public returns (DTokenMetaData[] memory) {
    DToken[] memory allMarkets = controller.getAllMarkets();
    DTokenMetaData[] memory result = new DTokenMetaData[](allMarkets.length);

    for(uint i = 0; i<allMarkets.length; i++){
      result[i].dTokenInfo = getDTokenInfo(allMarkets[i]);
    }
    return result;
  }

  function dTokenMetaDataListAuth(address payable account) public returns (DTokenMetaData[] memory) {
    DToken[] memory allMarkets = controller.getAllMarkets();
    DTokenMetaData[] memory result = new DTokenMetaData[](allMarkets.length);

    for(uint i = 0; i<allMarkets.length; i++){
      result[i].dTokenInfo = getDTokenInfo(allMarkets[i]);
      result[i].accountInfo = getAccountInfo(allMarkets[i], account);
    }
    return result;
  }

  function compareStrings(string memory a, string memory b) internal pure returns (bool) {
    return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
  }
}
