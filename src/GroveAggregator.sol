// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

contract GroveAggregaotor {
    address public owner;
    address public pendingOwner;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    function transferOwnership(address newOwner) public onlyOwner(){
        pendingOwner = newOwner;
    }

    function acceptOwnership() public {
        require(msg.sender == pendingOwner, "Not the pending owner");
        owner = pendingOwner;
        pendingOwner= address(0);
    }
}