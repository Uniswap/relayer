// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {ActionsLib} from "../../../src/lib/ActionsLib.sol";
import {MockUniversalRouter} from "../util/mock/MockUniversalRouter.sol";

contract ActionsLibTest is Test {
    address universalRouter;

    function setUp() public {
        universalRouter = address(new MockUniversalRouter());
    }

    function test_execute_succeedsWithEmptyActions() public {
        bytes[] memory actions = new bytes[](0);
        ActionsLib.execute(actions, universalRouter);
    }

    function test_execute_succeeds() public {
        bytes[] memory actions = new bytes[](1);
        actions[0] = abi.encodeWithSelector(MockUniversalRouter.succeeds.selector);
        ActionsLib.execute(actions, universalRouter);
    }

    function test_execute_succeedsWithReturn() public {
        bytes[] memory actions = new bytes[](1);
        actions[0] = abi.encodeWithSelector(MockUniversalRouter.succeedsWithReturn.selector);
        ActionsLib.execute(actions, universalRouter);
    }

    function test_reverts_mockUniversalRouter() public {
        bytes[] memory actions = new bytes[](1);
        actions[0] = abi.encode(bytes4(keccak256("FakeSelector()")));
        vm.expectRevert(MockUniversalRouter.UniversalRouterError.selector);
        ActionsLib.execute(actions, universalRouter);
    }
}
