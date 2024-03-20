// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.13;

import "forge-std/console2.sol";
import "forge-std/Script.sol";
import {RelayOrderReactor} from "../src/reactors/RelayOrderReactor.sol";

contract DeployRelayOrderReactor is Script {
    function setUp() public {}

    function run(address universalRouter) public returns (RelayOrderReactor reactor) {
        vm.startBroadcast();

        /// Should deploy the reactor using create2 to the address:
        /// 0x0000000000A4e21E2597DCac987455c48b12edBF
        reactor = new RelayOrderReactor{salt: 0x0000000000000000000000000000000000000000de21eb608bf4d3a312250060}(
            universalRouter
        );
        console2.log("Reactor", address(reactor));

        vm.stopBroadcast();
    }
}
