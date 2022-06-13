// v1.0.0 
// date : 2022-03-03
// author : jijay
pragma solidity ^0.5.6;
pragma experimental ABIEncoderV2;

import "../common/CarefulMath.sol";
import "../oracle/PriceOracle.sol";
import "../lending/Controller.sol";
import "../lending/DToken.sol";
import "../lending/DErc20.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";

interface IAggregator {
    function latestAnswer() external view returns (int256 answer);
    function decimals() external view returns (uint8);
}

interface IgOHM {
  function index() external view returns (uint256);
}

interface IUniswapV3Pool {
  struct Slot0 {
    uint160 sqrtPriceX96;
    int24 tick;
    uint16 observationIndex;
    uint16 observationCardinality;
    uint16 observationCardinalityNext;
    uint8 feeProtocol;
    bool unlocked;
  }
  function slot0() external view returns(Slot0 memory);
  function observe(uint32[] calldata secondsAgos) external view returns(int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s);
}

contract PriceOracleV2 is CarefulMath {
  uint256 public constant Q96 = 0x1000000000000000000000000;
  address public admin;

  // ChainLink
  address constant public KRW_USD = 0x01435677FB11763550905594A16B645847C1d0F3;
  address constant public USDT_USD = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;
  address constant public KNC_USD = 0xf8fF43E991A81e6eC886a3D281A2C6cC19aE70Fc;
  address constant public BTC_USD = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
  address constant public ETH_USD = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
  address constant public USDC_USD = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
  address constant public DAI_USD = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
  address constant public LINK_USD = 0x2c1d072e956AFFC0D435Cb7AC38EF18d24d9127c;
  address constant public SAND_USD = 0x35E3f7E558C04cE7eEE1629258EcbbA03B36Ec56;
  address constant public MANA_USD = 0x56a4857acbcfe3a66965c251628B1c9f1c408C19;
  address constant public OMG_USD = 0x7D476f061F8212A8C9317D5784e72B4212436E93;
  address constant public PLA_USD = 0xbc535B134DdF81fc83254a3D0Ed2C0C60144405E;
  address constant public SRM_ETH = 0x050c048c9a0CD0e76f166E2539F87ef2acCEC58f;
  address constant public SHIB_ETH = 0x8dD1CD88F43aF196ae478e91b9F5E4Ac69A97C61;
  address constant public DOGE_USD = 0x2465CefD3b488BE410b941b1d4b2767088e2A028;
  address constant public AXS_ETH = 0x8B4fC5b68cD50eAc1dD33f695901624a4a1A0A8b;
  address constant public OHM_ETH = 0x9a72298ae3886221820B1c878d12D872087D3a23;

  // Uniswap
  address constant public CNG_ETH = 0xfab26CFa923360fFC8ffc40827faeE5500988E9C;

  PriceOracle public priceOracle;
  Controller public controller;

  constructor(PriceOracle priceOracle_, Controller controller_) public {
    admin = msg.sender;
    priceOracle = priceOracle_;
    controller = controller_;
  }

  function setPriceOracle(PriceOracle newPriceOracle_) external {
    require(msg.sender == admin);
    priceOracle = newPriceOracle_;
  }

  function getData(address feed) public view returns(uint, uint){
      IAggregator priceFeed = IAggregator(feed);
      int price = priceFeed.latestAnswer();
      uint decimal = priceFeed.decimals(); 
      require(price != 0 && decimal != 0, "CHAINLINK_ZERO_VALUE");
      return (uint(price), decimal);
  }

  function getUnderlyingPrice(bytes32 symbol) public view returns (uint){

    uint krw = getKrwPrice();

    if(symbol == bytes32("USDT")) {
      (uint price, uint decimal) = getData(USDT_USD);

      // decimal : 6
      return price * krw * 1e18 * 1e12 / 10 ** decimal;
      
    } else if (symbol == bytes32("KNC")) {
      (uint price, uint decimal) = getData(KNC_USD);

      // decimal: 18
      return price * krw * 1e18 / 10 ** decimal;

    } else if (symbol == bytes32("WBTC")) {
      (uint price, uint decimal) = getData(BTC_USD);

      // decimal: 8
      return price * krw * 1e18 * 1e10 / 10 ** decimal;

    } else if (symbol == bytes32("ETH")) {
      (uint price, uint decimal) = getData(ETH_USD);

      // decimal: 18
      return price * krw * 1e18 / 10 ** decimal;

    } else if (symbol == bytes32("USDC")) {
      (uint price, uint decimal) = getData(USDC_USD);

      // decimal: 6
      return price * krw * 1e18 * 1e12 / 10 ** decimal;

    } else if (symbol == bytes32("DAI")) {
      (uint price, uint decimal) = getData(DAI_USD);

      // decimal: 18
      return price * krw * 1e18 / 10 ** decimal;

    } else if (symbol == bytes32("LINK")) {
      (uint price, uint decimal) = getData(LINK_USD);

      // decimal: 18
      return price * krw * 1e18 / 10 ** decimal;

    } else if (symbol == bytes32("SAND")) {
      (uint price, uint decimal) = getData(SAND_USD);

      // decimal: 18
      return price * krw * 1e18 / 10 ** decimal;

    } else if (symbol == bytes32("MANA")) {
      (uint price, uint decimal) = getData(MANA_USD);

      // decimal: 18
      return price * krw * 1e18 / 10 ** decimal;

    } else if (symbol == bytes32("OMG")) {
      (uint price, uint decimal) = getData(OMG_USD);

       // decimal: 18
      return price * krw * 1e18 / 10 ** decimal;

    } else if (symbol == bytes32("PLA")) {
      (uint price, uint decimal) = getData(PLA_USD);

      // decimal: 18
      return price * krw * 1e18 / 10 ** decimal;

    } else if (symbol == bytes32("SRM")) {
      (uint price, uint decimal) = getData(SRM_ETH);
      uint ethPrice = getEthUsdPrice();

      // decimal: 6
      return price * ethPrice * krw * 1e18 * 1e12 / 10 ** decimal;
      
    } else if (symbol == bytes32("SHIB")) {
      (uint price, uint decimal) = getData(SHIB_ETH);
      uint ethPrice = getEthUsdPrice();

      // decimal: 18
      return price * ethPrice * krw * 1e18 / 10 ** decimal;

    } else if (symbol == bytes32("renDOGE")) {
      (uint price, uint decimal) = getData(DOGE_USD);

      // decimal: 8
      return price * krw * 1e18 * 1e10 / 10 ** decimal;

    } else if (symbol == bytes32("CNG")) {
      IUniswapV3Pool cngEthPool = IUniswapV3Pool(CNG_ETH);

      uint ethPrice = getEthUsdPrice();
      uint32[] memory secondsAgos = new uint32[](2);
      // 20분
      uint32 twapInterval = 1200;

      secondsAgos[0] = twapInterval;
      secondsAgos[1] = 0;
      (int56[] memory tickCumulatives, ) = cngEthPool.observe(secondsAgos);

      uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(
        int24((tickCumulatives[1] - tickCumulatives[0]) / twapInterval)
      );

      uint priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
      // decimal: 18
      uint ratio = FullMath.mulDiv(priceX96, 1e18, Q96);

      return ratio * ethPrice * krw;

    } else if (symbol == bytes32("AXS")) {

      (uint price, uint decimal) = getData(AXS_ETH);
      uint ethPrice = getEthUsdPrice();

      // decimal: 18
      return price * ethPrice * krw * 1e18 / 10 ** decimal;

    } else if (symbol == bytes32("gOHM")) {

      (uint price, uint decimal) = getData(OHM_ETH);
      uint ethPrice = getEthUsdPrice();
      IgOHM gOHM = IgOHM(0x0ab87046fBb341D058F17CBC4c1133F25a20a52f);
      uint index = uint(gOHM.index());

      // decimal: 18
      // index decimal : 9
      return price * ethPrice * krw * 1e18 * index / 10 ** decimal / 1e9;

    }   

    return priceOracle.getUnderlyingPrice(symbol);

  }

  function getPrices() external view returns(bytes32[] memory, uint[] memory) {
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

      uint priceMantissa = getUnderlyingPrice(underlyingSymbol);
      uint additionalDecimals = uint8(18) - decimals;

      if (decimals == uint8(18)) {
        mantissa = 1;
      } else {
        mantissa = 10 ** additionalDecimals;
      }
      uint priceResult = priceMantissa / mantissa;

      prices[i] = priceResult;
      underlyingSymbols[i] = underlyingSymbol;
    }

    return (underlyingSymbols, prices);
  }

  function getKrwPrice() public view returns(uint) {
    (uint price, uint decimal) = getData(KRW_USD);
    return 10 ** decimal / price;
  }

  function getEthUsdPrice() public view returns(uint) {
    (uint price, uint decimal) = getData(ETH_USD);
    return price / 10 ** decimal;
  }
}
