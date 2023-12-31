// SPDX-license-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {OrderBook} from "../src/OrderBook.sol";

contract DeployOrderBook is Script {
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
    uint256 private constant CLOSE_FEE_PERCENTAGE = 75000; //0.075% 75000
    //This needs to be tested
    uint256 private constant BASE_BORROW_FEE_PERCENTAGE = 1000; // 0.001%/h or 1000

    int256[] private MAX_OPEN_INTEREST = [
        int256(500_000 ether),
        int256(500_000 ether),
        int256(500_000 ether),
        int256(500_000 ether),
        int256(500_000 ether)
    ];

    //Had some trouble returning arrays, bytes32 so I just made two deploy functions one for local and one for mainnet/testnet
    //TODO put more data into the helper function

    /*   sepoliaNetworkConfig = NetworkConfig({
            pythPriceFeedAddress: 0x2880aB155794e7179c9eE2e38200202908C17B43, //Sepolia pyth address
            //pythUpdateData: abi.encode(0x000000), //placeholder
            //priceFeedIdArray: PRICE_FEED_IDS,
            usdc: 0xC38B1dd611889Abc95d4E0a472A667c3671c08DE, //This is just a placeholder
            weth: 0xca80ba6dc32e08d06f1aa886011eed1d77c77be9eb761cc10d72b7d0a2fd57a6,
            wbtc: 0xf9c0172ba10dfa4d19088d94f5bf61d3b54d5bd7483a322a982e1373ee8ea31b,
            xrp: 0xbfaf7739cb6fe3e1c57a0ac08e1d931e9e6062d476fa57804e165ab572b5b621,
            matic: 0xd2c2c1f2bba8e0964f9589e060c2ee97f5e19057267ac3284caef3bd50bd2cb5,
            bnb: 0xecf553770d9b10965f8fb64771e93f5690a182edc32be4a3236e0caaa6e0581a,
            deployerKey: vm.envUint("PRIVATE_KEY")
        }); */
    //price feed Ids, were being returned in the helper config but arrays are a little tricky so it is here for now
    //Use this for deploying to a real testnet (price id's are the same for all testnets)
    //For deploing to mainnet these values will need to be changed, please see pythnetwork docs.
    bytes32[] private pythIdArray = [
        bytes32(0xca80ba6dc32e08d06f1aa886011eed1d77c77be9eb761cc10d72b7d0a2fd57a6), //ETH
        bytes32(0xf9c0172ba10dfa4d19088d94f5bf61d3b54d5bd7483a322a982e1373ee8ea31b), //BTC
        bytes32(0xbfaf7739cb6fe3e1c57a0ac08e1d931e9e6062d476fa57804e165ab572b5b621), //XRP
        bytes32(0xd2c2c1f2bba8e0964f9589e060c2ee97f5e19057267ac3284caef3bd50bd2cb5), //MATIC
        bytes32(0xecf553770d9b10965f8fb64771e93f5690a182edc32be4a3236e0caaa6e0581a) //BNB
    ];

    address pythPriceFeedAddress;
    address usdc;
    uint256 deployerKey;

    function run() external returns (OrderBook, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();

        (pythPriceFeedAddress, usdc, deployerKey) = helperConfig.activeNetworkConfig();

        vm.startBroadcast(deployerKey);

        orderBook =
        new OrderBook(address(pythPriceFeedAddress), address(usdc), pythIdArray, MAX_OPEN_INTEREST, PAIR_INDEX, PAIR_SYMBOL);

        vm.stopBroadcast();
        return (orderBook, helperConfig);
    }
}
