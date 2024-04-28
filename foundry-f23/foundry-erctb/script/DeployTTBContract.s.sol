// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Script} from  "../lib/forge-std/src/Script.sol";
import {TTBContract} from "../src/TokenTradeBuddy.sol";

contract DeployTTBContract is Script {
    function run() external returns (TTBContract){
        vm.startBroadcast();
        TTBContract ttbContract = new TTBContract();
        vm.stopBroadcast();
        return ttbContract;
    }
}