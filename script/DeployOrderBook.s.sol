// SPDX-license-Identifier: MIT

pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {OrderBook} from "../src/OrderBook.sol";

contract DeployOrderBook is Script {
    OrderBook public orderBook;

    //This is not necessary but already done maybe change later
    uint256 private constant ETH_INDEX = 0;
    uint256 private constant BTC_INDEX = 1;
    uint256[] private PAIR_INDEX = [ETH_INDEX, BTC_INDEX];
    //This is not necessary but already done maybe change later
    string private constant ETH_SYMBOL = "ETH/USD";
    string private constant BTC_SYMBOL = "BTC/USD";
    string[] private PAIR_SYMBOL = [ETH_SYMBOL, BTC_SYMBOL];

    uint256 private constant OPEN_FEE_PERCENTAGE = 75000; //0.075% or 75000
    uint256 private constant CLOSE_FEE_PERCENTAGE = 75000; //0.075% 75000
    //This needs to be tested
    uint256 private constant BASE_BORROW_FEE_PERCENTAGE = 1000; // 0.001%/h or 1000

    int256[] private MAX_OPEN_INTEREST = [int256(500_000 ether), int256(500_000 ether)];

    //price feed Ids, were being returned in the helper config but arrays are a little tricky so it is here for now
    //These are for testing and index 0 is ETH and index 1 is BTC
    bytes32[] private priceFeedIdArray = [
        bytes32(0x000000000000000000000000000000000000000000000000000000000000abcd),
        bytes32(0x0000000000000000000000000000000000000000000000000000000000001234)
    ];

    function run() external returns (OrderBook, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();

        (
            address pythPriceFeedAddress,
            bytes memory pythUpdateData,
            address usdc,
            address weth,
            address wbtc,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();

        //uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        orderBook =
        new OrderBook(address(pythPriceFeedAddress), address(usdc), priceFeedIdArray, MAX_OPEN_INTEREST, PAIR_INDEX, PAIR_SYMBOL);

        vm.stopBroadcast();
        return (orderBook, helperConfig);
    }
}
