// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {FeeEscalatorLib} from "../../../src/lib/FeeEscalatorLib.sol";
import {ReactorErrors} from "../../../src/base/ReactorErrors.sol";

contract FeeEscalatorLibTest is Test {
    function testRelayFeeEscalationNoEscalation(uint256 amount, uint256 decayStartTime, uint256 decayEndTime) public {
        vm.assume(decayEndTime >= decayStartTime);
        assertEq(FeeEscalatorLib.decay(amount, amount, decayStartTime, decayEndTime), amount);
    }

    function testRelayFeeEscalationNoEscalationYet() public {
        vm.warp(100);
        // at decayStartTime
        assertEq(FeeEscalatorLib.decay(1 ether, 2 ether, 100, 200), 1 ether);

        vm.warp(80);
        // before decayStartTime
        assertEq(FeeEscalatorLib.decay(1 ether, 2 ether, 100, 200), 1 ether);
    }

    function testRelayFeeEscalation() public {
        vm.warp(150);
        assertEq(FeeEscalatorLib.decay(1 ether, 2 ether, 100, 200), 1.5 ether);

        vm.warp(180);
        assertEq(FeeEscalatorLib.decay(1 ether, 2 ether, 100, 200), 1.8 ether);

        vm.warp(110);
        assertEq(FeeEscalatorLib.decay(1 ether, 2 ether, 100, 200), 1.1 ether);

        vm.warp(190);
        assertEq(FeeEscalatorLib.decay(1 ether, 2 ether, 100, 200), 1.9 ether);
    }

    function testRelayFeeEscalationFullyEscalated() public {
        vm.warp(200);
        assertEq(FeeEscalatorLib.decay(1 ether, 2 ether, 100, 200), 2 ether);

        vm.warp(250);
        assertEq(FeeEscalatorLib.decay(1 ether, 2 ether, 100, 200), 2 ether);
    }

    function testRelayFeeEscalationRevertsWithWrongEndStartTimes() public {
        vm.expectRevert(FeeEscalatorLib.EndTimeBeforeStartTime.selector);
        FeeEscalatorLib.decay(1 ether, 2 ether, 200, 100);
    }

    function testRelayFeeEscalationEqualAmounts(uint256 amount, uint256 decayStartTime, uint256 decayEndTime) public {
        vm.assume(decayEndTime >= decayStartTime);
        uint256 time = decayStartTime;
        bound(time, decayStartTime, decayStartTime);

        vm.warp(time);
        assertEq(FeeEscalatorLib.decay(amount, amount, decayStartTime, decayEndTime), amount);
    }

    function testRelayFeeEscalationInvalidAmounts() public {
        vm.expectRevert(FeeEscalatorLib.InvalidAmounts.selector);
        FeeEscalatorLib.decay(2 ether, 1 ether, 100, 200);
    }

    function testRelayFeeEscalationBounded(
        uint256 startAmount,
        uint256 endAmount,
        uint256 decayStartTime,
        uint256 decayEndTime
    ) public {
        vm.assume(endAmount > startAmount);
        vm.assume(decayEndTime >= decayStartTime);
        uint256 decayed = FeeEscalatorLib.decay(startAmount, endAmount, decayStartTime, decayEndTime);
        assertGe(decayed, startAmount);
        assertLe(decayed, endAmount);
    }
}
