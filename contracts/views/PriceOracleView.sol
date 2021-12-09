pragma solidity ^0.5.6;
pragma experimental ABIEncoderV2;

import "../lending/Controller.sol";
import "../lending/DToken.sol";
import "../lending/DErc20.sol";
import "../lending/IERC20.sol";
import "../common/upgradeable/Initializable.sol";
import "../common/CarefulMath.sol";
import "../oracle/PriceOracle.sol";


contract PriceOracleView is Initializable, CarefulMath, Exponential {

  PriceOracle public priceOracle;
  Controller public controller;

  event Dividing(uint a, uint b, bytes32 underlyingSymbol);

  function initialize(PriceOracle priceOracle_, Controller controller_) public initializer {
      priceOracle = priceOracle_;
      controller = controller_;
  }

  function getPrices() external view returns (bytes32[] memory, uint[] memory) {
    DToken[] memory markets = controller.getAllMarkets();
    bytes32[] memory underlyingSymbols = new bytes32[](markets.length);
    uint[] memory prices = new uint[](markets.length);
    uint8 decimals;
    uint mantissa;

    for (uint i = 0; i < markets.length; i++) {
      DToken dToken = DToken(markets[i]);
      bytes32 underlyingSymbol = dToken.underlyingSymbol();

      if (underlyingSymbol == bytes32("ETH")) {
        decimals = uint8(18);
      } else {
        decimals = IERC20(DErc20(address(markets[i])).underlying()).decimals();
      }

      uint priceMantissa = priceOracle.getUnderlyingPrice(underlyingSymbol);
      uint additionalDecimals = uint8(18) - decimals;

      if (decimals == uint8(18)) {
        mantissa = 1;
      } else {
        mantissa = 10 ** additionalDecimals;
      }
      uint priceResult = priceMantissa / mantissa / 1e18;

      prices[i] = priceResult;
      underlyingSymbols[i] = underlyingSymbol;
    }
    return (underlyingSymbols, prices);
  }

  function getPrice(bytes32 underlyingSymbol) external view returns (uint) {
    return priceOracle.getUnderlyingPrice(underlyingSymbol);
  }
}
