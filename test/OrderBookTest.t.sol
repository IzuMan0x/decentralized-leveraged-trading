//here we have the old test script for orderbook
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {OrderBook} from "../src/OrderBook.sol";
import {MockPyth} from "@pyth-sdk-solidity/MockPyth.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {console} from "forge-std/console.sol";

contract OrderBookTest is Test {
    MockPyth public mockPyth;

    OrderBook public orderBook;

    uint256 private constant OPEN_FEE_PERCENTAGE = 75000; //0.075% or 75000
    uint256 private constant CLOSE_FEE_PERCENTAGE = 75000; //0.075% 75000

    //This needs to be tested
    uint256 private constant BASE_BORROW_FEE_PERCENTAGE = 1000; // 0.001%/h or 1000

    //Pair Index 1 for eth 2 for btc
    uint256 private constant PAIR_INDEX_ETHER = 1;
    uint256 private constant AMOUNT_COLLATERAL = 1 ether;
    uint256 private constant LEVERAGE = 2;
    uint8 private constant ORDER_TYPE = 1;

    bytes32 constant BASE_PRICE_ID = 0x000000000000000000000000000000000000000000000000000000000000abcd;
    bytes32 constant QUOTE_PRICE_ID = 0x0000000000000000000000000000000000000000000000000000000000001234;

    ERC20Mock baseToken;
    address payable constant BASE_TOKEN_MINT = payable(0x0000000000000000000000000000000000000011);
    ERC20Mock quoteToken;
    address payable constant QUOTE_TOKEN_MINT = payable(0x0000000000000000000000000000000000000022);

    address payable constant DUMMY_TO = payable(0x0000000000000000000000000000000000000055);

    uint256 MAX_INT = 2 ** 256 - 1;

    function setUp() public {
        // Creating a mock of Pyth contract with 60 seconds validTimePeriod (for staleness)
        // and 1 wei fee for updating the price.
        mockPyth = new MockPyth(60, 1);

        baseToken = new ERC20Mock();

        /* orderBook = new OrderBook(
            address(mockPyth), address(baseToken), OPEN_FEE_PERCENTAGE, CLOSE_FEE_PERCENTAGE, BASE_BORROW_FEE_PERCENTAGE, BASE_PRICE_ID); */
    }

    function setupTokens() private {
        baseToken.mint(address(this), 100 ether);
    }
    //PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE

    function testMartketOrder() public {
        uint256 nothing = 200 ether;
    }
    /* setupTokens();
        bytes[] memory updateData = new bytes[](1);
        int32 basePrice = 1;

        // This is a dummy update data for Eth. It shows the price as $1000 +- $10 (with -5 exponent).
        updateData[0] = mockPyth.createPriceFeedUpdateData(
            BASE_PRICE_ID, basePrice * 100000, 10 * 100000, -5, basePrice * 100000, 10 * 100000, uint64(block.timestamp)
        );

        // Make sure the contract has enough funds to update the pyth feeds
        uint256 value = mockPyth.getUpdateFee(updateData);
        vm.deal(address(this), value + 1000 ether);

        baseToken.approve(address(orderBook), MAX_INT);

        orderBook.marketOrder{value: value}(PAIR_INDEX_ETHER, AMOUNT_COLLATERAL, LEVERAGE, ORDER_TYPE, updateData);

        uint256[] memory positionDetails = orderBook.getUserTradingPositionDetails(address(this), 1);

        //note console.log() does not accept a struct as a data type
        console.log("Something should be here", positionDetails[0]);
        console.log("Something should be here", positionDetails[1]);
        console.log("Something should be here", positionDetails[2]);
        console.log("Something should be here", positionDetails[3]);
        console.log("Something should be here", positionDetails[4]);
    } */

    /* function testSwap() public {
        setupTokens(20e18, 20e18, 20e18, 20e18);

        doSwap(10, 1, true, 1e18);

        assertEq(quoteToken.balanceOf(address(this)), 10e18 - 1);
        assertEq(baseToken.balanceOf(address(this)), 21e18);

        doSwap(10, 1, false, 1e18);

        assertEq(quoteToken.balanceOf(address(this)), 20e18 - 1);
        assertEq(baseToken.balanceOf(address(this)), 20e18);
    }

    function testWithdraw() public {
        setupTokens(10e18, 10e18, 10e18, 10e18);

        swap.withdrawAll();

        assertEq(quoteToken.balanceOf(address(this)), 20e18);
        assertEq(baseToken.balanceOf(address(this)), 20e18);
        assertEq(quoteToken.balanceOf(address(swap)), 0);
        assertEq(baseToken.balanceOf(address(swap)), 0);
    }

    receive() external payable {} */
}
