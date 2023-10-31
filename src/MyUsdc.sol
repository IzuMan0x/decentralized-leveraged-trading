// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MyUsdc is ERC20 {
    constructor() ERC20("stablecoin", "USDC") {
        _mint(address(0xF6D528a4215682Fe328535243B9295b309ed3a48), 1000000 * 10 ** decimals());
    }

    //This coin is for testing purposes thus anyone can mint it...

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
