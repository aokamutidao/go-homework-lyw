// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.7.0;

contract Counter {
    uint256 private count = 0;

    event CounterIncremented(uint256 newCount);
    event CounterDecremented(uint256 newCount);
    event CounterReset(uint256 newCount);

    function getCount() public view returns (uint256) {
        return count;
    }

    function increment() public {
        count += 1;
        emit CounterIncremented(count);
    }

    function decrement() public {
        require(count > 0, "Counter: cannot decrement below zero");
        count -= 1;
        emit CounterDecremented(count);
    }

    function reset() public {
        count = 0;
        emit CounterReset(count);
    }
}
