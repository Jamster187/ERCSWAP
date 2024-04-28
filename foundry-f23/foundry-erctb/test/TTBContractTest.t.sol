// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Test, console} from "../lib/forge-std/src/Test.sol";
import {TTBContract} from "../src/TokenTradeBuddy.sol";

contract TTBContractTest is Test {
    TTBContract ttbcontract;

    function setUp() external {
        ttbcontract = new TTBContract();
    }

    function testInit() external {
        // Test the owner is correctly set
        assertEq(ttbcontract.owner(), address(this), "Owner should be the deployer of the contract");

        // Test the initial trade state is correctly set to AssetSetup
        assertEq(uint(ttbcontract.currentTradeState()), uint(TTBContract.TradeState.AssetSetup), "Initial trade state should be AssetSetup");
    }


}