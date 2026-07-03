// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Counter} from "../src/Counter.sol";

/// Dependency-free tests (no forge-std): forge discovers any contract with
/// test-prefixed functions, and a revert marks the test as failed.
contract CounterTest {
    Counter internal counter;

    function setUp() public {
        counter = new Counter();
    }

    function test_SetNumber() public {
        counter.setNumber(42);
        require(counter.number() == 42, "setNumber failed");
    }

    function test_Increment() public {
        counter.increment();
        require(counter.number() == 1, "increment failed");
    }

    function test_Decrement() public {
        counter.setNumber(2);
        counter.decrement();
        require(counter.number() == 1, "decrement failed");
    }

    function test_DecrementRevertsAtZero() public {
        try counter.decrement() {
            revert("expected underflow revert");
        } catch {}
    }
}
