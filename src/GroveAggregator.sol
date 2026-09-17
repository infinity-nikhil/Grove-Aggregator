// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";

contract GroveAggregaotor {
    address public owner;
    address public pendingOwner;
    address public feeWallet;

    mapping(bytes32 => bool) public allowedV4Pool;

    uint16 public feeBps;  // 1 bps = 0.01% so by 100 max cap the dev can max charge upto 1% on each txn
    uint16 public constant HARD_CAP = 100;

    IERC20 public immutable usdg; //making usdg a valid token

    error FeeTooHigh();
    error ZeroAddress();
    error NotUsdgPool();

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

    function setFee(uint16 feeBps_) public {
        if(feeBps_ > HARD_CAP) revert FeeTooHigh();
        feeBps = feeBps_;  //this just sets the feeBps using this feeBps dev can max charge 1% 
    }

    function setFeeWallet(address feeWallet_) public {
        if(feeWallet_ == address(0)) revert ZeroAddress();
        feeWallet = feeWallet_;  //this sets the fees wallet whatever comes goes in this wallet
    }

    function _split(uint256 usdgLeg) internal view returns(uint256 fee, uint256 rest){
        fee = (usdgLeg * feeBps) / 10_000; //the fee and the rest
        rest = usdgLeg - fee;
    }

    function _skim(uint256 fee) internal {
        if (fee > 0) usdg.safeTransfer(feeWallet, fee); //by this usdg.safeTransfer(feeWallet, fee) becomes valid
    }


    function setV4PoolAllowed(PoolKey calldata key, bool ok) external onlyOwner {
        address c0 = Currency.unwrap(key.currency0);
        address c1 = Currency.unwrap(key.currency1);
        if (c0 != address(usdg) && c1 != address(usdg)) revert NotUsdgPool();
        bytes32 h = keccak256(abi.encode(key));
        allowedV4Pool[h] = ok;
    }
}