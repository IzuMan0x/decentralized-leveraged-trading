//here we have the old test script for orderbook
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {OrderBook} from "../src/OrderBook.sol";
import {DeployOrderBook} from "../script/DeployOrderBook.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {MockPyth} from "@pyth-sdk-solidity/MockPyth.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {console} from "forge-std/console.sol";

contract OrderBookTest is Test {
    MockPyth public mockPyth;
    OrderBook public orderBook;
    HelperConfig public helperConfig;
    ERC20Mock public erc20Mock;

    //Pair Index 0 for eth 1 for btc
    uint256 private constant PAIR_INDEX_ETHER = 0;
    uint256 private constant PAIR_INDEX_BTC = 1;
    uint256 private constant AMOUNT_COLLATERAL = 100 ether;
    uint256 private constant LEVERAGE = 10 * 1e6; //becasue the precision is 6 decimal
    uint8 private constant ORDER_TYPE = 0;

    //user trade index
    uint256 private constant USER_TRADE_INDEX_FIRST = 1;
    uint256 private constant USER_TRADE_INDEX_SECOND = 2;
    uint256 private constant USER_TRADE_INDEX_THIRD = 3;

    ERC20Mock baseToken;
    address payable constant BASE_TOKEN_MINT = payable(0x0000000000000000000000000000000000000011);
    ERC20Mock quoteToken;
    address payable constant QUOTE_TOKEN_MINT = payable(0x0000000000000000000000000000000000000022);

    address payable constant DUMMY_TO = payable(0x0000000000000000000000000000000000000055);

    uint256 MAX_INT = 2 ** 256 - 1;

    //network config
    address pythPriceFeedAddress;
    bytes pythUpdateData;
    bytes[] pythUpdateDataArray;
    address usdc;
    address weth;
    address wbtc;
    uint256 deployerKey;

    address traderBigMoney = makeAddr("traderBigMoney");

    function setUp() public {
        DeployOrderBook deployer = new DeployOrderBook();
        (orderBook, helperConfig) = deployer.run();

        (pythPriceFeedAddress, pythUpdateData, usdc, weth, wbtc, deployerKey) = helperConfig.activeNetworkConfig();
        pythUpdateDataArray = [pythUpdateData];
        ERC20Mock(usdc).approve(address(orderBook), MAX_INT);
        ERC20Mock(usdc).mint(traderBigMoney, 1_000_000 ether);
        vm.deal(traderBigMoney, 1_000 ether);
    }

    ///////////////////////
    // Constructor Tests //
    ///////////////////////
    bytes32[] public priceFeedIdArray;
    uint256[] public pairIndexArray;
    string[] public pairSymbolArray;

    function testRevertsIfArrayLengthsDontMatch() public {
        priceFeedIdArray = [
            bytes32(0x000000000000000000000000000000000000000000000000000000000000abcd),
            bytes32(0x0000000000000000000000000000000000000000000000000000000000001234)
        ];
        pairIndexArray = [0];
        pairSymbolArray = ["ETH/USD"];

        vm.expectRevert(OrderBook.OrderBook__ParameterArraysMustBeTheSameLength.selector);
        orderBook =
        new OrderBook(address(pythPriceFeedAddress), address(usdc), priceFeedIdArray, pairIndexArray, pairSymbolArray);
    }

    ////////////////////////////////
    // marketOrder Function Tests //
    ///////////////////////////////

    function testMarketOrderCanBeMadeAndRecorded() public {
        vm.startPrank(traderBigMoney);
        uint256 userUsdcBalance = ERC20Mock(usdc).balanceOf(traderBigMoney);
        uint256 userBalance = traderBigMoney.balance;
        console.log("User balance of ether is: ", userBalance);
        console.log("User balance of usdc is: ", userUsdcBalance);
        ERC20Mock(usdc).approve(address(orderBook), MAX_INT);
        orderBook.marketOrder{value: 1}(PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE, pythUpdateDataArray);

        vm.stopPrank();

        uint256 totalLongAmount = orderBook.getTotalLongAmount(PAIR_INDEX_ETHER);
        console.log("Total amount of longs open are: ", totalLongAmount);

        //user position array starts at 1 not zero... for each pairIndex it is possible to have three trades open
        // not sure how this will affect the UI ease of use
        OrderBook.PositionDetails memory positionDetails =
            orderBook.getUserTradingPositionDetails(traderBigMoney, PAIR_INDEX_ETHER, USER_TRADE_INDEX_FIRST);

        uint256 positionCollateral = positionDetails.collateralAfterFee;
        uint64 openPrice = positionDetails.openPrice;

        console.log("User position collateral is: ", positionCollateral);
        console.log("User open price was: ", openPrice);

        skip(36000);

        (int256 liquidationPriceInt, int256 borrowFeeAmountInt) =
            orderBook.getUserLiquidationPrice(traderBigMoney, PAIR_INDEX_ETHER, USER_TRADE_INDEX_FIRST);
        uint256 borrowFeeAmount = uint256(borrowFeeAmountInt);
        uint256 liquidationPrice = uint256(liquidationPriceInt);
        console.log("User borrow fee is: ", borrowFeeAmount);
        console.log("User liquidaion price is: ", liquidationPrice);
    }
}
