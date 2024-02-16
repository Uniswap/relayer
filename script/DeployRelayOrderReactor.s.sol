// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.13;

import "forge-std/console2.sol";
import "forge-std/Script.sol";
import {RelayOrderReactor} from "../src/reactors/RelayOrderReactor.sol";

contract DeployRelayOrderReactor is Script {
    function setUp() public {}

    function run(address universalRouter) public returns (RelayOrderReactor reactor) {
        vm.startBroadcast();

        reactor = new RelayOrderReactor{salt: 0x00}(universalRouter);
        console2.log("Reactor", address(reactor));

        vm.stopBroadcast();
    }
}
