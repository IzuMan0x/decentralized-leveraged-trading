// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {OrderBook} from "../src/OrderBook.sol";
import {DeployOrderBookForTests} from "../script/DeployOrderBookForTests.s.sol";
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
    int256 private constant MAX_OPEN_INTEREST = 500_000 ether;

    bytes32 constant ETH_PRICE_ID = 0x000000000000000000000000000000000000000000000000000000000000abcd;
    bytes32 constant BTC_PRICE_ID = 0x0000000000000000000000000000000000000000000000000000000000001234;

    //user trade index
    uint256 private constant USER_TRADE_INDEX_FIRST = 2;
    uint256 private constant USER_TRADE_INDEX_SECOND = 1;
    uint256 private constant USER_TRADE_INDEX_THIRD = 0;

    int256[] private MAX_OPEN_INTEREST_ARRAY = [int256(500_000 ether), int256(500_000 ether)];

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
    bytes32 weth;
    bytes32 wbtc;
    bytes32 xrp;
    bytes32 matic;
    bytes32 bnb;
    uint256 deployerKey;

    address traderBigMoney = makeAddr("traderBigMoney");
    address traderLoser = makeAddr("traderLoser");
    address liquidator = makeAddr("liquidator");

    function setUp() public {
        DeployOrderBookForTests deployer = new DeployOrderBookForTests();
        (orderBook, helperConfig) = deployer.run();

        (pythPriceFeedAddress, usdc, deployerKey) = helperConfig.activeNetworkConfig();

        //bytes[] memory updateDataArray = new bytes[](1);

        bytes memory updateData;

        // This is a dummy update data for Eth. It shows the price as $1000 +- $10 (with -5 exponent).
        int32 ethPrice = 1000;
        //int32 btcPrice = 2000;
        //Here we are updating the pyth price feed so we can read from it later
        updateData = MockPyth(pythPriceFeedAddress).createPriceFeedUpdateData(
            ETH_PRICE_ID, ethPrice * 100000, 10 * 100000, -5, ethPrice * 100000, 10 * 100000, uint64(block.timestamp)
        );
        pythUpdateDataArray = [updateData];
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
        new OrderBook(address(pythPriceFeedAddress), address(usdc), priceFeedIdArray, MAX_OPEN_INTEREST_ARRAY, pairIndexArray, pairSymbolArray);
    }

    ////////////////////////////////
    // marketOrder Function Tests //
    ///////////////////////////////
    //general note console.log() cannot handle int, structs and there are probably more types...

    function testMarketOrderOpenPriceIsCorrectLong() public {
        vm.startPrank(traderBigMoney);
        ERC20Mock(usdc).approve(address(orderBook), MAX_INT);
        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_LONG, pythUpdateDataArray
        );
        OrderBook.PositionDetails memory positionDetails =
            orderBook.getUserTradingPositionDetails(traderBigMoney, PAIR_INDEX_ETHER, USER_TRADE_INDEX_FIRST);
        int256 expextedOpenPrice = 1010 * 1e8;
        int256 openPrice = positionDetails.openPrice;
        assertEq(openPrice, expextedOpenPrice);
        vm.stopPrank();
    }

    function testMarketOrderOpenPriceIsCorrectShort() public {
        vm.startPrank(traderBigMoney);
        ERC20Mock(usdc).approve(address(orderBook), MAX_INT);
        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_SHORT, pythUpdateDataArray
        );
        OrderBook.PositionDetails memory positionDetails =
            orderBook.getUserTradingPositionDetails(traderBigMoney, PAIR_INDEX_ETHER, USER_TRADE_INDEX_FIRST);
        int256 expextedOpenPrice = 990 * 1e8;
        int256 openPrice = positionDetails.openPrice;
        //uint256[3] memory tradeSlots = orderBook.getUserOpenTradesForAsset(address(traderBigMoney), PAIR_INDEX_ETHER);
        assertEq(openPrice, expextedOpenPrice);
        vm.stopPrank();
    }

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

        OrderBook.PositionDetails memory positionDetails =
            orderBook.getUserTradingPositionDetails(traderBigMoney, PAIR_INDEX_ETHER, USER_TRADE_INDEX_FIRST);

        int256 positionCollateral = positionDetails.collateralAfterFee;
        int256 openPrice = positionDetails.openPrice;

        //console.log("User position collateral is: ", positionCollateral);
        //console.log("User open price was: ", openPrice);

        uint256 startTime = block.timestamp;
        //console.log("Current time is: ", startTime);

        skip(55 days);

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

        (int256 userPNLPre, int256 borrowFeePre) =
            orderBook.getUserLiquidationPrice(address(traderBigMoney), PAIR_INDEX_ETHER, USER_TRADE_INDEX_SECOND);
        console.log("user PNL and borrow fee for long is: ", uint256(userPNLPre), uint256(borrowFeePre));
        skip(13 days);

        orderBook.getAllUserOpenTrades(address(traderBigMoney));

        skip(1 days);

        (int256 userPNL, int256 borrowFee) =
            orderBook.getUserLiquidationPrice(address(traderBigMoney), PAIR_INDEX_ETHER, USER_TRADE_INDEX_FIRST);
        console.log("user PNL and borrow fee for long is: ", uint256(userPNL), uint256(borrowFee));
        (int256 userPNLShort, int256 borrowFeeShort) =
            orderBook.getUserLiquidationPrice(address(traderBigMoney), PAIR_INDEX_ETHER, USER_TRADE_INDEX_SECOND);
        console.log("user PNL and borrow fee short is: ", uint256(userPNLShort), uint256(borrowFeeShort));

        ERC20Mock(usdc).balanceOf(address(orderBook));
        ERC20Mock(usdc).allowance(address(orderBook), address(traderBigMoney));

        orderBook.orderClose{value: 1}(PAIR_INDEX_ETHER, USER_TRADE_INDEX_FIRST, pythUpdateDataArray);
        skip(1 hours);

        //All trades closed

        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_SHORT, pythUpdateDataArray
        );
        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_LONG, pythUpdateDataArray
        );
        skip(1 hours);
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
    /////////////////////
    //Limit Order Tests//
    /////////////////////

    function testLimitOrderCanBePlacedAndExecuted() public {
        vm.startPrank(traderBigMoney);
        ERC20Mock(usdc).approve(address(orderBook), MAX_INT);
        int256 targetPrice = 1000 * 1e8;
        orderBook.limitOrder(PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_LONG, targetPrice);
        vm.stopPrank();
        vm.startPrank(traderLoser);
        orderBook.getAllUserLimitOrders(address(traderBigMoney));
        // This is a dummy update data for Eth. It shows the price as $1000 +- $10 (with -5 exponent).
        int32 ethPrice = 1060;

        bytes[] memory updateDataArray = new bytes[](1);
        //Here we are updating the pyth price feed so we can read from it later
        updateDataArray[0] = MockPyth(pythPriceFeedAddress).createPriceFeedUpdateData(
            ETH_PRICE_ID, ethPrice * 100000, 10 * 100000, -5, ethPrice * 100000, 10 * 100000, uint64(block.timestamp)
        );
        orderBook.executeLimitOrder{value: 1}(address(traderBigMoney), PAIR_INDEX_ETHER, 2, updateDataArray);
    }

    function testLimitOrderWillRevertIfPriceSlippageIsTooHigh() public {
        vm.startPrank(traderBigMoney);
        ERC20Mock(usdc).approve(address(orderBook), MAX_INT);
        int256 targetPrice = 1000 * 1e8;
        orderBook.limitOrder(PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_LONG, targetPrice);
        vm.stopPrank();
        vm.startPrank(traderLoser);
        orderBook.getAllUserLimitOrders(address(traderBigMoney));
        // This is a dummy update data for Eth. It shows the price as $1000 +- $10 (with -5 exponent).
        int32 ethPrice = 1060;

        bytes[] memory updateDataArray = new bytes[](1);
        //Here we are updating the pyth price feed so we can read from it later
        updateDataArray[0] = MockPyth(pythPriceFeedAddress).createPriceFeedUpdateData(
            ETH_PRICE_ID, ethPrice * 100000, 10 * 100000, -5, ethPrice * 100000, 10 * 100000, uint64(block.timestamp)
        );
        vm.expectRevert(OrderBook.OrderBook__LimitOrderExecutionFailedTooMuchSlippage.selector);
        orderBook.executeLimitOrder{value: 1}(address(traderBigMoney), PAIR_INDEX_ETHER, 2, updateDataArray);
    }

    function testLimitOrderWillRevertMoreThanThreeTrades() public {
        vm.startPrank(traderBigMoney);
        ERC20Mock(usdc).approve(address(orderBook), MAX_INT);
        int256 targetPrice = 1000 * 1e8;
        orderBook.limitOrder(PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_LONG, targetPrice);
        orderBook.limitOrder(PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_LONG, targetPrice);
        orderBook.limitOrder(PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_LONG, targetPrice);
        orderBook.getAllUserLimitOrders(address(traderBigMoney));
        vm.expectRevert(OrderBook.OrderBook__MaxNumberOfTradesReachedForAssetPairLimitOrder.selector);
        orderBook.limitOrder(PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_LONG, targetPrice);

        vm.stopPrank();
        vm.startPrank(traderLoser);
    }

    function testLimitOrderWillRevertMax3TradesLastLimitOrder() public {
        vm.startPrank(traderBigMoney);
        ERC20Mock(usdc).approve(address(orderBook), MAX_INT);
        int256 targetPrice = 1000 * 1e8;
        orderBook.limitOrder(PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_LONG, targetPrice);
        orderBook.limitOrder(PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_LONG, targetPrice);
        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_LONG, pythUpdateDataArray
        );
        orderBook.getAllUserLimitOrders(address(traderBigMoney));
        vm.expectRevert(OrderBook.OrderBook__MaxNumberOfOpenTrades3Reached.selector);
        orderBook.limitOrder(PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_LONG, targetPrice);

        vm.stopPrank();
        vm.startPrank(traderLoser);
    }

    function testLimitOrderWillRevertMax3TradesLastMarket() public {
        vm.startPrank(traderBigMoney);
        ERC20Mock(usdc).approve(address(orderBook), MAX_INT);
        int256 targetPrice = 1000 * 1e8;
        orderBook.limitOrder(PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_LONG, targetPrice);
        orderBook.limitOrder(PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_LONG, targetPrice);
        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_LONG, pythUpdateDataArray
        );
        orderBook.getAllUserLimitOrders(address(traderBigMoney));
        vm.expectRevert(OrderBook.OrderBook__MaxNumberOfOpenTrades3Reached.selector);
        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_LONG, pythUpdateDataArray
        );

        vm.stopPrank();
        vm.startPrank(traderLoser);
    }

    ///////////////////
    //Modifier Tests//
    //////////////////

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
        // Zero collateral
        orderBook.marketOrder{value: 1}(PAIR_INDEX_ETHER, 0, LEVERAGE, ORDER_TYPE_LONG, pythUpdateDataArray);

        vm.stopPrank();

        vm.startPrank(traderBigMoney);
        ERC20Mock(usdc).approve(address(orderBook), MAX_INT);

        vm.expectRevert(OrderBook.OrderBook__NeedsMoreThanZero.selector);
        //Zero leverage
        orderBook.marketOrder{value: 1}(PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, 0, ORDER_TYPE_LONG, pythUpdateDataArray);

        vm.stopPrank();
    }

    function testMaxedOpenInterestReachedLongs() public {
        vm.startPrank(traderBigMoney);
        ERC20Mock(usdc).approve(address(orderBook), MAX_INT);

        vm.expectRevert(OrderBook.OrderBook__MaxOpenInterestReachedLongs.selector);
        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, MAX_OPEN_INTEREST + 1 ether, LEVERAGE, ORDER_TYPE_LONG, pythUpdateDataArray
        );

        vm.stopPrank();
    }

    function testMaxedOpenInterestReachedShorts() public {
        vm.startPrank(traderBigMoney);
        ERC20Mock(usdc).approve(address(orderBook), MAX_INT);

        vm.expectRevert(OrderBook.OrderBook__MaxOpenInterestShortsReached.selector);
        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, MAX_OPEN_INTEREST + 1 ether, LEVERAGE, ORDER_TYPE_SHORT, pythUpdateDataArray
        );

        vm.stopPrank();
    }

    function testRevertsIfUserTryingToCLoseNonExisitingPosition() public {
        vm.startPrank(traderBigMoney);
        ERC20Mock(usdc).approve(address(orderBook), MAX_INT);

        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_SHORT, pythUpdateDataArray
        );
        uint256 userTradesIdForPair = 0;
        vm.expectRevert(OrderBook.OrderBook__UserClosingNonExistingPosition.selector);
        orderBook.orderClose(PAIR_INDEX_ETHER, userTradesIdForPair, pythUpdateDataArray);

        vm.stopPrank();
    }

    function testTradeSizeTooSmall() public {
        vm.startPrank(traderBigMoney);
        ERC20Mock(usdc).approve(address(orderBook), MAX_INT);
        int256 collaterTooSmall = 10 ether;
        vm.expectRevert(OrderBook.OrderBook__TradeSizeTooSmall.selector);
        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, collaterTooSmall, LEVERAGE, ORDER_TYPE_SHORT, pythUpdateDataArray
        );
        vm.stopPrank();
    }
    ///////////////////////////////
    // View and getter functions //
    ///////////////////////////////

    //This is 　test of the old function that resulted in math over/underflow

    function testGetCurrentBorrowRateForPairNew() public {
        vm.startPrank(traderBigMoney);
        orderBook.getCurrentBorrowRate(PAIR_INDEX_ETHER);
    }

    function testGetAllUserOpenTrades() public {
        vm.startPrank(traderBigMoney);
        ERC20Mock(usdc).approve(address(orderBook), MAX_INT);

        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_SHORT, pythUpdateDataArray
        );

        orderBook.getAllUserOpenTrades(address(traderBigMoney));
        vm.stopPrank();
    }

    function testUserOpenTradesForAsset() public {
        vm.startPrank(traderBigMoney);
        ERC20Mock(usdc).approve(address(orderBook), MAX_INT);

        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_SHORT, pythUpdateDataArray
        );
        uint256[3] memory expectedTradeSlots = [uint256(0), uint256(0), uint256(1)];

        uint256[3] memory tradeSlots = orderBook.getUserOpenTradesForAsset(address(traderBigMoney), PAIR_INDEX_ETHER);
        //Cannot compare arrays yet
        assertEq(tradeSlots[0], expectedTradeSlots[0]);
        vm.stopPrank();
    }

    function testGetUserLiquidationPriceShort() public {
        vm.startPrank(traderBigMoney);
        ERC20Mock(usdc).approve(address(orderBook), MAX_INT);

        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_SHORT, pythUpdateDataArray
        );

        orderBook.getUserLiquidationPrice(address(traderBigMoney), PAIR_INDEX_ETHER, USER_TRADE_INDEX_FIRST);
        vm.stopPrank();
    }

    function testGetUserLiquidationPriceLong() public {
        vm.startPrank(traderBigMoney);
        ERC20Mock(usdc).approve(address(orderBook), MAX_INT);

        orderBook.marketOrder{value: 1}(
            PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE_LONG, pythUpdateDataArray
        );
        skip(52 days);
        orderBook.getUserLiquidationPrice(address(traderBigMoney), PAIR_INDEX_ETHER, USER_TRADE_INDEX_FIRST);
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
        skip(65 days);

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

    function testChangeContractOwnership() public {
        vm.startPrank(vm.addr(deployerKey));
        orderBook.transferOwnership(traderBigMoney);
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
}
