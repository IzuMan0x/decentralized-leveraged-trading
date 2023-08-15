// SPDX-license-Identifier: MIT

pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {OrderBook} from "../src/OrderBook.sol";

contract DeployOrderBook is Script {
    OrderBook public orderBook;

    //This is not necessary but already done maybe change later
    uint256 private constant ETH_INDEX = 1;
    uint256 private constant BTC_INDEX = 2;
    uint256[] private PAIR_INDEX = [ETH_INDEX, BTC_INDEX];
    //This is not necessary but already done maybe change later
    string private constant ETH_SYMBOL = "ETH/USD";
    string private constant BTC_SYMBOL = "BTC/USD";
    string[] private PAIR_SYMBOL = [ETH_SYMBOL, BTC_SYMBOL];

    uint256 private constant OPEN_FEE_PERCENTAGE = 75000; //0.075% or 75000
    uint256 private constant CLOSE_FEE_PERCENTAGE = 75000; //0.075% 75000
    //This needs to be tested
    uint256 private constant BASE_BORROW_FEE_PERCENTAGE = 1000; // 0.001%/h or 1000
    //why are these not working??????
    //uint256[] public PAIR_INDEX = [0, 1];
    //string[] public PAIR_SYMBOL = ["ETH/USD", "BTC/USD"];

    //Pyth
    bytes32 constant ETH_PRICE_ID = 0x000000000000000000000000000000000000000000000000000000000000abcd;
    bytes32 constant BTC_PRICE_ID = 0x0000000000000000000000000000000000000000000000000000000000001234;
    bytes32[] private PRICE_FEED_ID_ARRAY = [ETH_PRICE_ID, BTC_PRICE_ID];

    function run() external returns (OrderBook) {
        HelperConfig helperConfig = new HelperConfig();

        (address pythPriceFeedAddress, address usdc,,, uint256 deployerKey) = helperConfig.activeNetworkConfig();

        //uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        orderBook =
        new OrderBook(address(pythPriceFeedAddress), address(usdc), OPEN_FEE_PERCENTAGE, CLOSE_FEE_PERCENTAGE, BASE_BORROW_FEE_PERCENTAGE, PRICE_FEED_ID_ARRAY, PAIR_INDEX, PAIR_SYMBOL);

        vm.stopBroadcast();
        return (orderBook);
    }
}
