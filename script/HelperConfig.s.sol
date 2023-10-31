// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {MockPyth} from "@pyth-sdk-solidity/MockPyth.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
//************************* Useful foundry terminal Commands *****************
//Paste the following into the command line to deploy the contract on a local testnet
// forge script script/DeployOrderBookForTests.s.sol:DeployOrderBookForTests --rpc-url http://127.0.0.1:8545 --broadcast
// Change the nonce of a certain address on local testnet
// cast nonce 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 --rpc-url http://127.0.0.1:8545
//sets the timestamp for the next block (cannot be less than the previous)
//cast rpc evm_setNextBlockTimestamp 3700000000000000000 --rpc-url http://127.0.0.1:8545
//For deploying to sepolia testnet
// forge script script/DeployOrderBook.s.sol:DeployOrderBook --rpc-url https://eth-sepolia.g.alchemy.com/v2/LraANW_-kPa50uFESPmaMoYH6rd-UJ-9 --broadcast

// Verifying a contract after deployment on Etherscan in this example the chain is the Sepolia testnet
// Additional setup: There constructor args are in a separate file (these will be the args you deployed the contract with) and the Etherscan API key is in the .env file
/* forge verify-contract --watch --chain-id 11155111 --compiler-version "v0.8.19+commit.7dd6d404" \
  --constructor-args-path constructor-args.txt 0xbfe0FEc7BBe8f61e7D2da4157f1469B5818e0857 src/OrderBook.sol:OrderBook */

contract HelperConfig is Script {
    NetworkConfig public activeNetworkConfig;

    struct NetworkConfig {
        address pythPriceFeedAddress;
        address usdc;
        uint256 deployerKey;
    }

    uint256 public DEFAULT_ANVIL_PRIVATE_KEY = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    //currently this is set for sepolia chain of 11155111

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    //  wethUsdPriceFeed: 0xca80ba6dc32e08d06f1aa886011eed1d77c77be9eb761cc10d72b7d0a2fd57a6, // ETH / USD
    //wbtcUsdPriceFeed: 0xf9c0172ba10dfa4d19088d94f5bf61d3b54d5bd7483a322a982e1373ee8ea31b, // BTC / USD

    function getSepoliaConfig() public view returns (NetworkConfig memory sepoliaNetworkConfig) {
        //bytes32[2] memory PRICE_FEED_IDS = [ETH_PRICE_ID, BTC_PRICE_ID];
        sepoliaNetworkConfig = NetworkConfig({
            pythPriceFeedAddress: 0x2880aB155794e7179c9eE2e38200202908C17B43, //Sepolia pyth address
            //pythUpdateData: abi.encode(0x000000), //placeholder
            //priceFeedIdArray: PRICE_FEED_IDS,
            usdc: 0x40a945CC51F76e1409584242fec3ccAbE2402e88, //This ERC20 token deployed on the Sepolia network
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory anvilNetworkConfig) {
        // Check to see if we set an active network config
        if (activeNetworkConfig.pythPriceFeedAddress != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast(DEFAULT_ANVIL_PRIVATE_KEY);

        // Creating a mock of Pyth contract with 10hrs validTimePeriod (for staleness)
        // and 1 wei fee for updating the price. Do not change this 🥲, front-end relies on this being the same
        // for test purposes we not care about staleness thus 2e50😜
        // by default this contract will use the latest price update
        MockPyth mockPyth = new MockPyth(2e50, 1);

        ERC20Mock usdcMock = new ERC20Mock();

        //public address of the default anvil account
        usdcMock.mint(address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266), 1_000_000 ether);

        vm.stopBroadcast();

        anvilNetworkConfig = NetworkConfig({
            pythPriceFeedAddress: address(mockPyth),
            usdc: address(usdcMock),
            deployerKey: DEFAULT_ANVIL_PRIVATE_KEY
        });
    }
}
