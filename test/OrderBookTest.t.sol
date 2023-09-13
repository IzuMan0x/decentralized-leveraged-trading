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
    uint256 private constant INVALID_PAIR_INDEX = 5;
    int256 private constant AMOUNT_COLLATERAL = 1000 ether;
    int256 private constant LEVERAGE = 10 * 1e6; //becasue the precision is 6 decimal
    int256 private constant MAX_LEVERAGE = 150 * 1e6;
    int256 private constant OVER_LEVERAGED = 151 * 1e6;
    uint8 private constant ORDER_TYPE_LONG = 0;
    uint8 private constant ORDER_TYPE_SHORT = 1;

    bytes32 constant ETH_PRICE_ID = 0x000000000000000000000000000000000000000000000000000000000000abcd;
    bytes32 constant BTC_PRICE_ID = 0x0000000000000000000000000000000000000000000000000000000000001234;

    //user trade index
    uint256 private constant USER_TRADE_INDEX_FIRST = 2;
    uint256 private constant USER_TRADE_INDEX_SECOND = 1;
    uint256 private constant USER_TRADE_INDEX_THIRD = 0;

    int256[] private MAX_OPEN_INTEREST = [int256(500_000 ether), int256(500_000 ether)];

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
    address traderLoser = makeAddr("traderLoser");
    address liquidator = makeAddr("liquidator");

    function setUp() public {
        DeployOrderBook deployer = new DeployOrderBook();
        (orderBook, helperConfig) = deployer.run();

        (pythPriceFeedAddress, pythUpdateData, usdc, weth, wbtc, deployerKey) = helperConfig.activeNetworkConfig();
        //Starting price is set in the helper config currently set @ $1000
        pythUpdateDataArray = [pythUpdateData];
        ERC20Mock(usdc).approve(address(orderBook), MAX_INT);
        ERC20Mock(usdc).mint(traderBigMoney, 1_000_000 ether);
        ERC20Mock(usdc).mint(traderLoser, 1_000_000 ether);
        vm.deal(traderBigMoney, 1_000 ether);
        vm.deal(traderLoser, 1_000 ether);
        vm.deal(liquidator, 1_000 ether);
        vm.startPrank(traderLoser);
        ERC20Mock(usdc).approve(address(orderBook), MAX_INT);
        vm.stopPrank();
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
        new OrderBook(address(pythPriceFeedAddress), address(usdc), priceFeedIdArray, MAX_OPEN_INTEREST, pairIndexArray, pairSymbolArray);
    }

    ////////////////////////////////
    // marketOrder Function Tests //
    ///////////////////////////////
    //general note console.log() cannot handle int, structs and there are probably more types...

    function testMarketOrderCanBeMadeAndRecorded() public {
        //traderBigMoney is opening his winning trade😜
        vm.startPrank(traderBigMoney);
        uint256 userUsdcBalance = ERC20Mock(usdc).balanceOf(traderBigMoney);
        uint256 userBalance = traderBigMoney.balance;
        console.log("User balance of ether is: ", userBalance);
        console.log("User balance of usdc is: ", userUsdcBalance);
        ERC20Mock(usdc).approve(address(orderBook), MAX_INT);
        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_LONG, pythUpdateDataArray
        );

        vm.stopPrank();

        int256 totalLongAmount = orderBook.getTotalLongAmount(PAIR_INDEX_ETHER);
        console.log("Total amount of longs open are: ", uint256(totalLongAmount));

        //user position array starts at 1 not zero... for each pairIndex it is possible to have three trades open
        // not sure how this will affect the UI ease of use
        OrderBook.PositionDetails memory positionDetails =
            orderBook.getUserTradingPositionDetails(traderBigMoney, PAIR_INDEX_ETHER, USER_TRADE_INDEX_FIRST);

        int256 positionCollateral = positionDetails.collateralAfterFee;
        int256 openPrice = positionDetails.openPrice;

        //console.log("User position collateral is: ", positionCollateral);
        //console.log("User open price was: ", openPrice);

        uint256 startTime = block.timestamp;
        //console.log("Current time is: ", startTime);

        skip(45 days);

        //trader will be in liquidation zone

        (int256 liquidationPriceInt, int256 borrowFeeAmountInt) =
            orderBook.getUserLiquidationPrice(traderBigMoney, PAIR_INDEX_ETHER, USER_TRADE_INDEX_FIRST);
        uint256 borrowFeeAmount = uint256(borrowFeeAmountInt);
        uint256 liquidationPrice = uint256(liquidationPriceInt);
        console.log("User borrow fee is: ", borrowFeeAmount);
        console.log("User liquidaion price is: ", liquidationPrice);

        vm.startPrank(liquidator);

        bytes[] memory updateDataArray = new bytes[](1);

        bytes memory updateData;

        // This is a dummy update data for Eth. It shows the price as $1000 +- $10 (with -5 exponent).
        int32 ethPrice = 1000;
        int32 btcPrice = 2000;
        //Here we are updating the pyth price feed so we can read from it later
        updateDataArray[0] = MockPyth(pythPriceFeedAddress).createPriceFeedUpdateData(
            ETH_PRICE_ID, ethPrice * 100000, 10 * 100000, -5, ethPrice * 100000, 10 * 100000, uint64(block.timestamp)
        );

        (int256 liquidationPriceInt2, int256 borrowFeeAmountInt2) =
            orderBook.getUserLiquidationPrice(traderBigMoney, PAIR_INDEX_ETHER, USER_TRADE_INDEX_FIRST);

        uint256 value = MockPyth(pythPriceFeedAddress).getUpdateFee(updateDataArray);
        OrderBook.PositionDetails memory positionDetailsAfterTimePassed =
            orderBook.getUserTradingPositionDetails(traderBigMoney, PAIR_INDEX_ETHER, USER_TRADE_INDEX_FIRST);

        orderBook.liquidateUser{value: 1}(traderBigMoney, PAIR_INDEX_ETHER, USER_TRADE_INDEX_FIRST, updateDataArray);

        vm.stopPrank();
    }

    function testSimpleOpenAndCloseATrade() public {
        vm.startPrank(traderBigMoney);
        ERC20Mock(usdc).approve(address(orderBook), MAX_INT);
        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_LONG, pythUpdateDataArray
        );
        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_SHORT, pythUpdateDataArray
        );
        skip(13 days);

        orderBook.getAllUserOpenTrades(address(traderBigMoney));

        skip(1 days);

        (int256 userPNL, int256 borrowFee) =
            orderBook.getUserLiquidationPrice(address(traderBigMoney), PAIR_INDEX_ETHER, USER_TRADE_INDEX_FIRST);
        console.log("user PNL and borrow fee for long is: ", uint256(userPNL), uint256(borrowFee));
        (int256 userPNLShort, int256 borrowFeeShort) =
            orderBook.getUserLiquidationPrice(address(traderBigMoney), PAIR_INDEX_ETHER, USER_TRADE_INDEX_SECOND);
        console.log("user PNL and borrow fee short is: ", uint256(userPNLShort), uint256(borrowFeeShort));

        orderBook.orderClose{value: 1}(PAIR_INDEX_ETHER, USER_TRADE_INDEX_FIRST, pythUpdateDataArray);
        vm.stopPrank();
    }

    function testOpeningMaxTradesEveryPair() public {
        vm.startPrank(traderBigMoney);
        ERC20Mock(usdc).approve(address(orderBook), MAX_INT);
        int64 btcPrice = 2000;
        bytes[] memory updateDataArrayBtc = new bytes[](1);
        updateDataArrayBtc[0] = MockPyth(pythPriceFeedAddress).createPriceFeedUpdateData(
            BTC_PRICE_ID, btcPrice * 100000, 10 * 100000, -5, btcPrice * 100000, 10 * 100000, uint64(block.timestamp)
        );
        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_LONG, pythUpdateDataArray
        );
        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_SHORT, pythUpdateDataArray
        );
        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_LONG, pythUpdateDataArray
        );
        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_BTC, AMOUNT_COLLATERAL + 100 ether, LEVERAGE, ORDER_TYPE_LONG, updateDataArrayBtc
        );
        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_BTC, AMOUNT_COLLATERAL + 200 ether, LEVERAGE, ORDER_TYPE_SHORT, updateDataArrayBtc
        );
        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_BTC, AMOUNT_COLLATERAL + 300 ether, LEVERAGE, ORDER_TYPE_LONG, updateDataArrayBtc
        );
        skip(1000);
        orderBook.getAllUserOpenTrades(address(traderBigMoney));
        vm.stopPrank();
    }

    function testOnlyThreeOpenTradesPerPair() public {
        //traderBigMoney is opening his winning trade😜
        vm.startPrank(traderBigMoney);
        ERC20Mock(usdc).approve(address(orderBook), MAX_INT);
        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_LONG, pythUpdateDataArray
        );
        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_LONG, pythUpdateDataArray
        );
        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_LONG, pythUpdateDataArray
        );
        vm.expectRevert(OrderBook.OrderBook__MaxNumberOfOpenTrades3Reached.selector);
        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_LONG, pythUpdateDataArray
        );

        vm.stopPrank();
    }

    function testMaxLeverageIs150AndRevertsIfOver150() public {
        vm.startPrank(traderBigMoney);
        ERC20Mock(usdc).approve(address(orderBook), MAX_INT);
        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, MAX_LEVERAGE, ORDER_TYPE_LONG, pythUpdateDataArray
        );

        vm.expectRevert(OrderBook.OrderBook__MaxLeverageIs150.selector);
        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, OVER_LEVERAGED, ORDER_TYPE_LONG, pythUpdateDataArray
        );

        vm.stopPrank();
    }

    function testTradeCanOnlyBeOpenedWithValidPair() public {
        vm.startPrank(traderBigMoney);
        ERC20Mock(usdc).approve(address(orderBook), MAX_INT);

        vm.expectRevert(OrderBook.OrderBook__InvalidTradingPair.selector);
        orderBook.marketOrder{value: 1}(
            INVALID_PAIR_INDEX, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_LONG, pythUpdateDataArray
        );

        vm.stopPrank();
    }

    function testTradeOfAmountZeroCannotBeOpened() public {
        vm.startPrank(traderBigMoney);
        ERC20Mock(usdc).approve(address(orderBook), MAX_INT);

        vm.expectRevert(OrderBook.OrderBook__NeedsMoreThanZero.selector);
        orderBook.marketOrder{value: 1}(PAIR_INDEX_ETHER, 0, LEVERAGE, ORDER_TYPE_LONG, pythUpdateDataArray);

        vm.stopPrank();

        vm.startPrank(traderBigMoney);
        ERC20Mock(usdc).approve(address(orderBook), MAX_INT);

        vm.expectRevert(OrderBook.OrderBook__NeedsMoreThanZero.selector);
        orderBook.marketOrder{value: 1}(PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, 0, ORDER_TYPE_LONG, pythUpdateDataArray);

        vm.stopPrank();
    }

    function testTraderCanBeLiquidatedByPriceChange() public {
        vm.startPrank(traderBigMoney);
        ERC20Mock(usdc).approve(address(orderBook), MAX_INT);
        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_LONG, pythUpdateDataArray
        );

        bytes[] memory updateDataArray = new bytes[](1);

        bytes memory updateData;
        skip(10);

        // This is a dummy update data for Eth. It shows the price as $1000 +- $10 (with -5 exponent).
        int32 ethPrice = 900;
        int32 btcPrice = 2000;
        //Here we are updating the pyth price feed so we can read from it later
        updateDataArray[0] = MockPyth(pythPriceFeedAddress).createPriceFeedUpdateData(
            ETH_PRICE_ID, ethPrice * 100000, 10 * 100000, -5, ethPrice * 100000, 10 * 100000, uint64(block.timestamp)
        );
        orderBook.liquidateUser{value: 1}(traderBigMoney, PAIR_INDEX_ETHER, USER_TRADE_INDEX_FIRST, updateDataArray);

        vm.stopPrank();
    }

    function testTraderCanBeLiquidatedByBorrowFees() public {
        vm.startPrank(traderBigMoney);
        ERC20Mock(usdc).approve(address(orderBook), MAX_INT);
        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_LONG, pythUpdateDataArray
        );

        bytes[] memory updateDataArray = new bytes[](1);

        bytes memory updateData;
        skip(55 days);

        // This is a dummy update data for Eth. It shows the price as $1000 +- $10 (with -5 exponent).
        int32 ethPrice = 1020;
        int32 btcPrice = 2000;
        //Here we are updating the pyth price feed so we can read from it later
        updateDataArray[0] = MockPyth(pythPriceFeedAddress).createPriceFeedUpdateData(
            ETH_PRICE_ID, ethPrice * 100000, 10 * 100000, -5, ethPrice * 100000, 10 * 100000, uint64(block.timestamp)
        );
        orderBook.liquidateUser{value: 1}(traderBigMoney, PAIR_INDEX_ETHER, USER_TRADE_INDEX_FIRST, updateDataArray);

        vm.stopPrank();
    }

    function testOpenAndCloseATrade() public {
        vm.startPrank(traderBigMoney);
        ERC20Mock(usdc).approve(address(orderBook), MAX_INT);
        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_LONG, pythUpdateDataArray
        );
        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_SHORT, pythUpdateDataArray
        );
        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_LONG, pythUpdateDataArray
        );

        /* orderBook.marketOrder{value: 1}(
            PAIR_INDEX_BTC, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_LONG, pythUpdateDataArray
        ) */

        bytes[] memory updateDataArray = new bytes[](1);

        bytes memory updateData;
        skip(1000);

        // This is a dummy update data for Eth. It shows the price as $1000 +- $10 (with -5 exponent).
        int32 ethPrice = 500;
        int32 btcPrice = 2000;
        //Here we are updating the pyth price feed so we can read from it later
        updateDataArray[0] = MockPyth(pythPriceFeedAddress).createPriceFeedUpdateData(
            ETH_PRICE_ID, ethPrice * 100000, 10 * 100000, -5, ethPrice * 100000, 10 * 100000, uint64(block.timestamp)
        );
        orderBook.orderClose{value: 1}(PAIR_INDEX_ETHER, USER_TRADE_INDEX_FIRST, updateDataArray);
        orderBook.orderClose{value: 1}(PAIR_INDEX_ETHER, USER_TRADE_INDEX_SECOND, updateDataArray);
        orderBook.orderClose{value: 1}(PAIR_INDEX_ETHER, USER_TRADE_INDEX_THIRD, updateDataArray);

        skip(1000);

        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_LONG, pythUpdateDataArray
        );
        skip(1000);
        orderBook.orderClose{value: 1}(PAIR_INDEX_ETHER, USER_TRADE_INDEX_FIRST, updateDataArray);

        vm.stopPrank();
    }

    function testMarketOrdersAreCorrectlyStoredInMapping() public {
        vm.startPrank(traderBigMoney);
        ERC20Mock(usdc).approve(address(orderBook), MAX_INT);
        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_LONG, pythUpdateDataArray
        );
        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_SHORT, pythUpdateDataArray
        );
        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_LONG, pythUpdateDataArray
        );
        OrderBook.PositionDetails memory userPositionDetailsFirstTrade =
            orderBook.getUserTradingPositionDetails(address(traderBigMoney), PAIR_INDEX_ETHER, 1);
        OrderBook.PositionDetails memory userPositionDetailsSecondTrade =
            orderBook.getUserTradingPositionDetails(address(traderBigMoney), PAIR_INDEX_ETHER, 2);
        OrderBook.PositionDetails memory userPositionDetailsThirdTrade =
            orderBook.getUserTradingPositionDetails(address(traderBigMoney), PAIR_INDEX_ETHER, 3);

        vm.stopPrank();
    }

    function testDifferentUsersCanOpenAndCloseTradesNormaly() public {
        vm.startPrank(traderBigMoney);
        ERC20Mock(usdc).approve(address(orderBook), MAX_INT);
        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_LONG, pythUpdateDataArray
        );
        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_SHORT, pythUpdateDataArray
        );
        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_LONG, pythUpdateDataArray
        );
        OrderBook.PositionDetails memory userPositionDetailsFirstTrade =
            orderBook.getUserTradingPositionDetails(address(traderBigMoney), PAIR_INDEX_ETHER, 1);
        OrderBook.PositionDetails memory userPositionDetailsSecondTrade =
            orderBook.getUserTradingPositionDetails(address(traderBigMoney), PAIR_INDEX_ETHER, 2);
        OrderBook.PositionDetails memory userPositionDetailsThirdTrade =
            orderBook.getUserTradingPositionDetails(address(traderBigMoney), PAIR_INDEX_ETHER, 3);

        vm.stopPrank();
        vm.startPrank(traderLoser);
        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_LONG, pythUpdateDataArray
        );
        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_SHORT, pythUpdateDataArray
        );
        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_LONG, pythUpdateDataArray
        );
        vm.stopPrank();
    }

    ////////////////////
    //getter functions//
    ////////////////////
    /// note if a user opens a trade and immediately calculates PNL (through getter or orderClose etc.) there will be a math error division by 0 since (openTime - currentTime) will result in 0
    /// note currently there is no closing fee
    function testGetUserLiquidationPrice() public {
        vm.startPrank(traderBigMoney);
        ERC20Mock(usdc).approve(address(orderBook), MAX_INT);
        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_LONG, pythUpdateDataArray
        );
        skip(1000);
        OrderBook.PositionDetails memory userPositionDetailsFirstTrade =
            orderBook.getUserTradingPositionDetails(address(traderBigMoney), PAIR_INDEX_ETHER, 2);

        orderBook.getUserLiquidationPrice(address(traderBigMoney), PAIR_INDEX_ETHER, 2);
    }
}
