/* // SPDX-license-Identifier: MIT

pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {OrderBook} from "../src/OrderBook.sol";

contract DeployOrderBook is Script {
    uint256 depositInterval = 30 days;
    uint256 withdrawInterval = 365 days;
    uint256 actionWindow = 48 hours;

    function run() external returns (OrderBook) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        OrderBook orderBook = new OrderBook(depositInterval, withdrawInterval, actionWindow);

        vm.stopBroadcast();
        return (orderBook);
    }
} */
