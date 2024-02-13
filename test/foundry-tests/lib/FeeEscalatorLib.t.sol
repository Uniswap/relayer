// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {FeeEscalator} from "../../../src/base/ReactorStructs.sol";
import {FeeEscalatorLib} from "../../../src/lib/FeeEscalatorLib.sol";
import {ReactorErrors} from "../../../src/base/ReactorErrors.sol";

contract FeeEscalatorLibTest is Test {
    using FeeEscalatorLib for FeeEscalator;

    function testRelayFeeEscalationNoEscalation(uint256 amount, uint256 startTime, uint256 endTime) public {
        vm.assume(endTime >= startTime);
        assertEq(FeeEscalatorLib.resolve(amount, amount, startTime, endTime), amount);
    }

    function testRelayFeeEscalationNoEscalationYet() public {
        vm.warp(100);
        // at startTime
        assertEq(FeeEscalatorLib.resolve(1 ether, 2 ether, 100, 200), 1 ether);

        vm.warp(80);
        // before startTime
        assertEq(FeeEscalatorLib.resolve(1 ether, 2 ether, 100, 200), 1 ether);
    }

    function testRelayFeeEscalation() public {
        vm.warp(150);
        assertEq(FeeEscalatorLib.resolve(1 ether, 2 ether, 100, 200), 1.5 ether);

        vm.warp(180);
        assertEq(FeeEscalatorLib.resolve(1 ether, 2 ether, 100, 200), 1.8 ether);

        vm.warp(110);
        assertEq(FeeEscalatorLib.resolve(1 ether, 2 ether, 100, 200), 1.1 ether);

        vm.warp(190);
        assertEq(FeeEscalatorLib.resolve(1 ether, 2 ether, 100, 200), 1.9 ether);
    }

    function testRelayFeeEscalationFullyEscalated() public {
        vm.warp(200);
        assertEq(FeeEscalatorLib.resolve(1 ether, 2 ether, 100, 200), 2 ether);

        vm.warp(250);
        assertEq(FeeEscalatorLib.resolve(1 ether, 2 ether, 100, 200), 2 ether);
    }

    function testRelayFeeEscalationRevertsWithWrongEndStartTimes() public {
        vm.expectRevert(FeeEscalatorLib.EndTimeBeforeStartTime.selector);
        FeeEscalatorLib.resolve(1 ether, 2 ether, 200, 100);
    }

    function testRelayFeeEscalationEqualAmounts(uint256 amount, uint256 startTime, uint256 endTime) public {
        vm.assume(endTime >= startTime);
        uint256 time = startTime;
        bound(time, startTime, startTime);

        vm.warp(time);
        assertEq(FeeEscalatorLib.resolve(amount, amount, startTime, endTime), amount);
    }

    function testRelayFeeEscalationInvalidAmounts() public {
        vm.expectRevert(FeeEscalatorLib.InvalidAmounts.selector);
        FeeEscalatorLib.resolve(2 ether, 1 ether, 100, 200);
    }

    function testRelayFeeEscalationBounded(uint256 startAmount, uint256 endAmount, uint256 startTime, uint256 endTime)
        public
    {
        vm.assume(endAmount > startAmount);
        vm.assume(endTime >= startTime);
        uint256 resolved = FeeEscalatorLib.resolve(startAmount, endAmount, startTime, endTime);
        assertGe(resolved, startAmount);
        assertLe(resolved, endAmount);
    }

    function testToTokenPermissions() public {
        address token = makeAddr("token");
        FeeEscalator memory fee = FeeEscalator({
            token: token,
            startAmount: 1 ether,
            endAmount: 2 ether,
            startTime: 100,
            endTime: 200,
            recipient: address(0)
        });
        ISignatureTransfer.TokenPermissions memory permission = fee.toTokenPermissions();
        assertEq(permission.token, token);
        // should be endAmount
        assertEq(permission.amount, 2 ether);
    }

    function testToTransferDetailsWithSpecifiedRecipient() public {
        address filler = makeAddr("filler");
        FeeEscalator memory fee = FeeEscalator({
            token: address(this),
            startAmount: 1 ether,
            endAmount: 1 ether,
            startTime: 0,
            endTime: 0,
            recipient: address(this)
        });
        ISignatureTransfer.SignatureTransferDetails memory details = fee.toTransferDetails(filler);
        assertEq(details.to, address(this));
        assertEq(details.requestedAmount, 1 ether);
    }

    function testToTransferDetailsWithNoRecipient() public {
        address filler = makeAddr("filler");
        FeeEscalator memory fee = FeeEscalator({
            token: address(this),
            startAmount: 1 ether,
            endAmount: 1 ether,
            startTime: 0,
            endTime: 0,
            recipient: address(0)
        });
        ISignatureTransfer.SignatureTransferDetails memory details = fee.toTransferDetails(filler);
        assertEq(details.to, filler);
        assertEq(details.requestedAmount, 1 ether);
    }
}
