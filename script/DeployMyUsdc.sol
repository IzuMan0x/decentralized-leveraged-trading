// SPDX-license-Identifier: MIT

pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {MyUsdc} from "../src/MyUsdc.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Simple ERC20 token Deploy Script
/// @author IzuMan
/// @notice Deploys an ERC20 Token
/// @dev Private key needs to be defined in the .env file (env file needs to be in the main folder of the Foundry project)

contract DeployMyUsdc is Script {
    function run() public returns (ERC20) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);
        MyUsdc usdc = new MyUsdc();

        vm.stopBroadcast();
        return usdc;
    }
}
