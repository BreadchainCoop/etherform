// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// Minimal fixture contract used by etherform's end-to-end workflow tests.
/// Deliberately dependency-free so the fixture needs no submodules or node_modules.
contract Counter {
    uint256 public number;

    function setNumber(uint256 newNumber) public {
        number = newNumber;
    }

    function increment() public {
        number += 1;
    }

    function decrement() public {
        require(number > 0, "Counter: underflow");
        number -= 1;
    }
}
