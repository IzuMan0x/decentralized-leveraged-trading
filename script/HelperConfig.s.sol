// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {MockPyth} from "@pyth-sdk-solidity/MockPyth.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
//Paste the follwing into the command line to deploy the contract on a local testnet
//forge script script/DeployOrderBook.s.sol:DeployOrderBook --rpc-url http://127.0.0.1:8545 --broadcast

contract HelperConfig is Script {
    NetworkConfig public activeNetworkConfig;

    bytes32 constant ETH_PRICE_ID = 0x000000000000000000000000000000000000000000000000000000000000abcd;
    bytes32 constant BTC_PRICE_ID = 0x0000000000000000000000000000000000000000000000000000000000001234;

    struct NetworkConfig {
        address pythPriceFeedAddress;
        bytes pythUpdateData;
        //bytes32[2] priceFeedIdArray;
        address usdc;
        address weth;
        address wbtc;
        uint256 deployerKey;
    }

    uint256 public DEFAULT_ANVIL_PRIVATE_KEY = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;

    constructor() {
        if (block.chainid == 280) {
            activeNetworkConfig = getZkEraGoerliConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    //  wethUsdPriceFeed: 0xca80ba6dc32e08d06f1aa886011eed1d77c77be9eb761cc10d72b7d0a2fd57a6, // ETH / USD
    //wbtcUsdPriceFeed: 0xf9c0172ba10dfa4d19088d94f5bf61d3b54d5bd7483a322a982e1373ee8ea31b, // BTC / USD

    function getZkEraGoerliConfig() public view returns (NetworkConfig memory zkEraGoerliNetworkConfig) {
        //bytes32[2] memory PRICE_FEED_IDS = [ETH_PRICE_ID, BTC_PRICE_ID];
        zkEraGoerliNetworkConfig = NetworkConfig({
            pythPriceFeedAddress: 0xC38B1dd611889Abc95d4E0a472A667c3671c08DE, //zkEraTestNet
            pythUpdateData: abi.encode(0x000000), //placeholder
            //priceFeedIdArray: PRICE_FEED_IDS,
            usdc: 0xC38B1dd611889Abc95d4E0a472A667c3671c08DE, //This is just a placeholder
            weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81, //Not sure where to find the address for zkEra
            wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory anvilNetworkConfig) {
        bytes32[2] memory PRICE_FEED_IDS = [ETH_PRICE_ID, BTC_PRICE_ID];
        // Check to see if we set an active network config
        if (activeNetworkConfig.pythPriceFeedAddress != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast(DEFAULT_ANVIL_PRIVATE_KEY);

        // Creating a mock of Pyth contract with 60 seconds validTimePeriod (for staleness)
        // and 1 wei fee for updating the price.
        MockPyth mockPyth = new MockPyth(60, 1);

        bytes[] memory updateDataArray = new bytes[](2);
        bytes memory updateData;

        // This is a dummy update data for Eth. It shows the price as $1000 +- $10 (with -5 exponent).
        int32 ethPrice = 1000;
        int32 btcPrice = 2000;
        //Here we are updating the pyth price feed so we can read from it later
        updateDataArray[0] = mockPyth.createPriceFeedUpdateData(
            ETH_PRICE_ID, ethPrice * 100000, 10 * 100000, -5, ethPrice * 100000, 10 * 100000, uint64(block.timestamp)
        );
        updateDataArray[1] = mockPyth.createPriceFeedUpdateData(
            BTC_PRICE_ID, btcPrice * 100000, 10 * 100000, -5, btcPrice * 100000, 10 * 100000, uint64(block.timestamp)
        );

        updateData = mockPyth.createPriceFeedUpdateData(
            ETH_PRICE_ID, ethPrice * 100000, 10 * 100000, -5, ethPrice * 100000, 10 * 100000, uint64(block.timestamp)
        );

        // Make sure the contract has enough funds to update the pyth feeds
        uint256 value = mockPyth.getUpdateFee(updateDataArray);
        vm.deal(address(this), value);

        ERC20Mock usdcMock = new ERC20Mock();
        usdcMock.mint(address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266), 1_000_000 ether);

        ERC20Mock wethMock = new ERC20Mock();

        ERC20Mock wbtcMock = new ERC20Mock();

        vm.stopBroadcast();

        anvilNetworkConfig = NetworkConfig({
            pythPriceFeedAddress: address(mockPyth),
            pythUpdateData: updateData,
            //priceFeedIdArray: PRICE_FEED_IDS,
            usdc: address(usdcMock),
            weth: address(wethMock),
            wbtc: address(wbtcMock),
            deployerKey: DEFAULT_ANVIL_PRIVATE_KEY
        });
    }
}
