// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.13;

import "forge-std/console2.sol";
import "forge-std/Script.sol";
import {RelayOrderReactor} from "../src/reactors/RelayOrderReactor.sol";

contract RelayOrderReactorInitBytecode is Script {
    function setUp() public {}

    function run(address universalRouter) public {
        bytes memory args = abi.encode(universalRouter);
        bytes memory initcode = abi.encodePacked(vm.getCode("RelayOrderReactor.sol:RelayOrderReactor"), args);

        bytes32 initcodeHash = keccak256(initcode);

        vm.writeFile(".artifacts/init_code", vm.toString(initcode));
        vm.writeFile(".artifacts/init_code_hash", vm.toString(initcodeHash));

        console2.logBytes32(initcodeHash);
    }
}
