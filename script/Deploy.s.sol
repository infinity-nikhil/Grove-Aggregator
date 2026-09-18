// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {GroveAggregator} from "../src/GroveAggregator.sol";

contract Deploy is Script {
    function run() external returns (GroveAggregator aggregator) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address poolManager = vm.envAddress("POOL_MANAGER");
        address usdg = vm.envAddress("USDG");
        address permit2 = vm.envAddress("PERMIT2");
        address owner = vm.envAddress("OWNER");
        address feeWallet = vm.envAddress("FEE_WALLET");
        uint16 feeBps = uint16(vm.envUint("FEE_BPS"));

        vm.startBroadcast(deployerPrivateKey);

        aggregator = new GroveAggregator(
            poolManager,
            usdg,
            permit2,
            owner,
            feeWallet,
            feeBps
        );

        vm.stopBroadcast();
    }
}

//About the depolyement we have to know this that we cannot deploy the direct contract itself,
//we need a deploy script. WHY ?? good question cause foundary demands it's no special reason 
//And we have passed all the requires params of the construcor in .env file instead of hardcoding 
// inside the command line and also tested this on the local net by forking the robinhood chain

//the command goes like: -
// source .env
// forge script script/Deploy.s.sol:Deploy \
//   --rpc-url http://127.0.0.1:8545 \
//   --broadcast 