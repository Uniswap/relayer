// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

library UnsafeSignedMath {
    function mul(uint256 a, int256 b) internal pure returns (int256) {
        unchecked {
            return int256(a) * b;
        }
    }

    function mul(int256 a, uint256 b) internal pure returns (int256) {
        unchecked {
            return a * int256(b);
        }
    }
}
