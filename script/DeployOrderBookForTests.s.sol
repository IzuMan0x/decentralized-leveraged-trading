// SPDX-license-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {OrderBook} from "../src/OrderBook.sol";

contract DeployOrderBookForTests is Script {
    OrderBook public orderBook;

    //This is not necessary but already done maybe change later
    uint256 private constant ETH_INDEX = 0;
    uint256 private constant BTC_INDEX = 1;
    uint256 private constant XRP_INDEX = 2;
    uint256 private constant MATIC_INDEX = 3;
    uint256 private constant BNB_INDEX = 4;

    uint256[] private PAIR_INDEX = [ETH_INDEX, BTC_INDEX, XRP_INDEX, MATIC_INDEX, BNB_INDEX];
    //This is not necessary but already done maybe change later
    string private constant ETH_SYMBOL = "ETH/USD";
    string private constant BTC_SYMBOL = "BTC/USD";
    string private constant XRP_SYMBOL = "XRP/USD";
    string private constant MATIC_SYMBOL = "MATIC/USD";
    string private constant BNB_SYMBOL = "BNB/USD";

    string[] private PAIR_SYMBOL = [ETH_SYMBOL, BTC_SYMBOL, XRP_SYMBOL, MATIC_SYMBOL, BNB_SYMBOL];
    bytes32[] priceFeedIdArray;

    uint256 private constant OPEN_FEE_PERCENTAGE = 75000; //0.075% or 75000
    uint256 private constant CLOSE_FEE_PERCENTAGE = 75000; //0.075% or 75000

    uint256 private constant BASE_BORROW_FEE_PERCENTAGE = 1000; // 0.001%/h or 1000

    //Max amount of usd that will be allowed per pair
    int256[] private MAX_OPEN_INTEREST = [
        int256(500_000 ether),
        int256(500_000 ether),
        int256(500_000 ether),
        int256(500_000 ether),
        int256(500_000 ether)
    ];

    //price feed Ids, were being returned in the helper config but arrays are a little tricky so it is here for now
    //These are for testing and index 0 is ETH and index 1 is BTC
    //This is for a mock/local testnet
    bytes32[] private priceFeedIdArrayMock = [
        bytes32(0x000000000000000000000000000000000000000000000000000000000000abcd),
        bytes32(0x0000000000000000000000000000000000000000000000000000000000001234),
        bytes32(0x0000000000000000000000000000000000000000000000000000000000004321),
        bytes32(0x000000000000000000000000000000000000000000000000000000000000dcba),
        bytes32(0x0000000000000000000000000000000000000000000000000000000000009876)
    ];

    address pythPriceFeedAddress;

    address usdc;

    uint256 deployerKey;

    function run() external returns (OrderBook, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();

        (pythPriceFeedAddress, usdc, deployerKey) = helperConfig.activeNetworkConfig();

        vm.startBroadcast(deployerKey);

        orderBook =
        new OrderBook(address(pythPriceFeedAddress), address(usdc), priceFeedIdArrayMock, MAX_OPEN_INTEREST, PAIR_INDEX, PAIR_SYMBOL);

        vm.stopBroadcast();
        return (orderBook, helperConfig);
    }
}
