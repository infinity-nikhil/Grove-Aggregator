// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/types/BalanceDelta.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {ISignatureTransfer} from "./IDex.sol";

//important thing regarding the update like previously we used to import as v4-core/src
//now the thing is we don't have to add that src directly go for types or interface 
//And the swappram it is no more in the module it is inside the ipoolmanager so whenever we need
//swapparams we will be doing ipoolmanager.swapparams something like this 

contract GroveAggregator is IUnlockCallback, ReentrancyGuard {
    using BalanceDeltaLibrary for BalanceDelta;
    using SafeERC20 for IERC20;

    uint16 public constant HARD_CAP = 100;
    uint256 public constant MAX_LEGS = 8;

    IPoolManager public immutable poolManager;
    IERC20 public immutable usdg;
    ISignatureTransfer public immutable permit2;

    address public owner;
    address public pendingOwner;
    address public feeWallet;
    uint16 public feeBps;

    mapping(bytes32 => bool) public allowedV4Pool;

    struct Leg {
        PoolKey v4Key;
        uint256 portionBps;
    }

    error NotOwner();
    error NotPendingOwner();
    error NotPoolManager();
    error ZeroAddress();
    error FeeTooHigh();
    error Slippage();
    error NotZeroAfter();
    error Expired();
    error BadLegCount();
    error BadSplit();
    error PermitTokenMismatch();
    error PoolNotAllowed();
    error NotUsdgPool();

    event Bought(address indexed swapper, address indexed stock, uint256 usdgIn, uint256 stockOut, uint256 fee);
    event Sold(address indexed swapper, address indexed stock, uint256 stockIn, uint256 usdgToUser, uint256 fee);
    event Swapped(
        address indexed swapper, address indexed stockIn, address indexed stockOut, uint256 amountIn, uint256 amountOut, uint256 usdgMid
    );
    event FeeSet(uint16 feeBps);
    event FeeWalletSet(address feeWallet);
    event V4PoolAllowed(bytes32 indexed keyHash, bool allowed);
    event OwnershipTransferStarted(address indexed newOwner);
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);
    event Rescued(address indexed token, address indexed to, uint256 amount);

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address poolManager_, address usdg_, address permit2_, address owner_, address feeWallet_, uint16 feeBps_) {
        if (poolManager_ == address(0) || usdg_ == address(0) || permit2_ == address(0) || owner_ == address(0) || feeWallet_ == address(0)) {
            revert ZeroAddress();
        }
        if (feeBps_ > HARD_CAP) revert FeeTooHigh();
        poolManager = IPoolManager(poolManager_);
        usdg = IERC20(usdg_);
        permit2 = ISignatureTransfer(permit2_);
        owner = owner_;
        feeWallet = feeWallet_;
        feeBps = feeBps_;
    }

    function setFee(uint16 feeBps_) external onlyOwner {
        if (feeBps_ > HARD_CAP) revert FeeTooHigh();
        feeBps = feeBps_;
        emit FeeSet(feeBps_);
    }

    function setFeeWallet(address feeWallet_) external onlyOwner {
        if (feeWallet_ == address(0)) revert ZeroAddress();
        feeWallet = feeWallet_;
        emit FeeWalletSet(feeWallet_);
    }

    function setV4PoolAllowed(PoolKey calldata key, bool ok) external onlyOwner {
        address c0 = Currency.unwrap(key.currency0);
        address c1 = Currency.unwrap(key.currency1);
        if (c0 != address(usdg) && c1 != address(usdg)) revert NotUsdgPool();
        bytes32 h = keccak256(abi.encode(key));
        allowedV4Pool[h] = ok;
        emit V4PoolAllowed(h, ok);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(newOwner);
    }

    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert NotPendingOwner();
        emit OwnerChanged(owner, pendingOwner);
        owner = pendingOwner;
        pendingOwner = address(0);
    }

    function rescue(address token, address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        if (token == address(0)) {
            (bool ok,) = to.call{value: amount}("");
            require(ok, "eth send failed");
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
        emit Rescued(token, to, amount);
    }

    function buy(address stock, uint256 usdgIn, uint256 minStockOut, Leg[] calldata legs, uint256 deadline)
        external
        nonReentrant
        returns (uint256 stockOut)
    {
        if (block.timestamp > deadline) revert Expired();
        if (minStockOut == 0) revert Slippage();
        _checkLegs(legs);
        usdg.safeTransferFrom(msg.sender, address(this), usdgIn);
        stockOut = _buyHeld(stock, usdgIn, minStockOut, legs);
    }

    function buyWithPermit(
        address stock,
        uint256 usdgIn,
        uint256 minStockOut,
        Leg[] calldata legs,
        uint256 deadline,
        ISignatureTransfer.PermitTransferFrom calldata permit,
        bytes calldata signature
    ) external nonReentrant returns (uint256 stockOut) {
        if (block.timestamp > deadline) revert Expired();
        if (minStockOut == 0) revert Slippage();
        _checkLegs(legs);
        _pullPermit(address(usdg), usdgIn, permit, signature);
        stockOut = _buyHeld(stock, usdgIn, minStockOut, legs);
    }

    function _buyHeld(address stock, uint256 usdgIn, uint256 minStockOut, Leg[] calldata legs)
        internal
        returns (uint256 stockOut)
    {
        uint256 u0 = usdg.balanceOf(address(this)) - usdgIn;
        uint256 s0 = IERC20(stock).balanceOf(address(this));

        (uint256 fee, uint256 swapUsdg) = _split(usdgIn);
        _skim(fee);

        stockOut = _route(legs, address(usdg), stock, swapUsdg);
        if (stockOut < minStockOut) revert Slippage();
        IERC20(stock).safeTransfer(msg.sender, stockOut);

        _noRetain(stock, u0, s0);
        emit Bought(msg.sender, stock, usdgIn, stockOut, fee);
    }

    function sell(address stock, uint256 stockIn, uint256 minUsdgOut, Leg[] calldata legs, uint256 deadline)
        external
        nonReentrant
        returns (uint256 usdgToUser)
    {
        if (block.timestamp > deadline) revert Expired();
        if (minUsdgOut == 0) revert Slippage();
        _checkLegs(legs);
        IERC20(stock).safeTransferFrom(msg.sender, address(this), stockIn);
        usdgToUser = _sellHeld(stock, stockIn, minUsdgOut, legs);
    }

    function sellWithPermit(
        address stock,
        uint256 stockIn,
        uint256 minUsdgOut,
        Leg[] calldata legs,
        uint256 deadline,
        ISignatureTransfer.PermitTransferFrom calldata permit,
        bytes calldata signature
    ) external nonReentrant returns (uint256 usdgToUser) {
        if (block.timestamp > deadline) revert Expired();
        if (minUsdgOut == 0) revert Slippage();
        _checkLegs(legs);
        _pullPermit(stock, stockIn, permit, signature);
        usdgToUser = _sellHeld(stock, stockIn, minUsdgOut, legs);
    }

    function _sellHeld(address stock, uint256 stockIn, uint256 minUsdgOut, Leg[] calldata legs)
        internal
        returns (uint256 usdgToUser)
    {
        uint256 u0 = usdg.balanceOf(address(this));
        uint256 s0 = IERC20(stock).balanceOf(address(this)) - stockIn;

        uint256 usdgOut = _route(legs, stock, address(usdg), stockIn);
        (uint256 fee, uint256 net) = _split(usdgOut);
        usdgToUser = net;
        if (usdgToUser < minUsdgOut) revert Slippage();

        _skim(fee);
        usdg.safeTransfer(msg.sender, usdgToUser);

        _noRetain(stock, u0, s0);
        emit Sold(msg.sender, stock, stockIn, usdgToUser, fee);
    }

    function swap(
        address stockIn,
        address stockOut,
        uint256 amountIn,
        uint256 minOut,
        Leg[] calldata sellLegs,
        Leg[] calldata buyLegs,
        uint256 deadline
    ) external nonReentrant returns (uint256 tokensOut) {
        if (block.timestamp > deadline) revert Expired();
        if (minOut == 0) revert Slippage();
        _checkLegs(sellLegs);
        _checkLegs(buyLegs);
        IERC20(stockIn).safeTransferFrom(msg.sender, address(this), amountIn);
        tokensOut = _swapHeld(stockIn, stockOut, amountIn, minOut, sellLegs, buyLegs);
    }

    function swapWithPermit(
        address stockIn,
        address stockOut,
        uint256 amountIn,
        uint256 minOut,
        Leg[] calldata sellLegs,
        Leg[] calldata buyLegs,
        uint256 deadline,
        ISignatureTransfer.PermitTransferFrom calldata permit,
        bytes calldata signature
    ) external nonReentrant returns (uint256 tokensOut) {
        if (block.timestamp > deadline) revert Expired();
        if (minOut == 0) revert Slippage();
        _checkLegs(sellLegs);
        _checkLegs(buyLegs);
        _pullPermit(stockIn, amountIn, permit, signature);
        tokensOut = _swapHeld(stockIn, stockOut, amountIn, minOut, sellLegs, buyLegs);
    }

    function _swapHeld(
        address stockIn,
        address stockOut,
        uint256 amountIn,
        uint256 minOut,
        Leg[] calldata sellLegs,
        Leg[] calldata buyLegs
    ) internal returns (uint256 tokensOut) {
        uint256 u0 = usdg.balanceOf(address(this));
        uint256 in0 = IERC20(stockIn).balanceOf(address(this)) - amountIn;
        uint256 out0 = IERC20(stockOut).balanceOf(address(this));

        uint256 usdgMid = _route(sellLegs, stockIn, address(usdg), amountIn);
        (uint256 fee, uint256 net) = _split(usdgMid);
        _skim(fee);

        tokensOut = _route(buyLegs, address(usdg), stockOut, net);
        if (tokensOut < minOut) revert Slippage();
        IERC20(stockOut).safeTransfer(msg.sender, tokensOut);

        if (usdg.balanceOf(address(this)) > u0) revert NotZeroAfter();
        if (IERC20(stockIn).balanceOf(address(this)) > in0) revert NotZeroAfter();
        if (IERC20(stockOut).balanceOf(address(this)) > out0) revert NotZeroAfter();
        emit Swapped(msg.sender, stockIn, stockOut, amountIn, tokensOut, usdgMid);
    }

    function _pullPermit(
        address token,
        uint256 amountIn,
        ISignatureTransfer.PermitTransferFrom calldata permit,
        bytes calldata signature
    ) internal {
        if (permit.permitted.token != token) revert PermitTokenMismatch();
        permit2.permitTransferFrom(
            permit,
            ISignatureTransfer.SignatureTransferDetails({to: address(this), requestedAmount: amountIn}),
            msg.sender,
            signature
        );
    }

    function _checkLegs(Leg[] calldata legs) internal view {
        uint256 n = legs.length;
        if (n == 0 || n > MAX_LEGS) revert BadLegCount();
        uint256 sum;
        for (uint256 i; i < n; ++i) {
            sum += legs[i].portionBps;
            if (!allowedV4Pool[keccak256(abi.encode(legs[i].v4Key))]) revert PoolNotAllowed();
        }
        if (sum != 10_000) revert BadSplit();
    }

    function _split(uint256 usdgLeg) internal view returns (uint256 fee, uint256 rest) {
        fee = (usdgLeg * feeBps) / 10_000;
        rest = usdgLeg - fee;
    }

    function _skim(uint256 fee) internal {
        if (fee > 0) usdg.safeTransfer(feeWallet, fee);
    }

    function _route(Leg[] calldata legs, address tokenIn, address tokenOut, uint256 amountIn)
        internal
        returns (uint256 out)
    {
        uint256 before = IERC20(tokenOut).balanceOf(address(this));
        uint256 spent;
        uint256 n = legs.length;
        for (uint256 i; i < n; ++i) {
            uint256 slice = i == n - 1 ? amountIn - spent : (amountIn * legs[i].portionBps) / 10_000;
            spent += slice;
            bool zeroForOne = Currency.unwrap(legs[i].v4Key.currency0) == tokenIn;
            poolManager.unlock(abi.encode(legs[i].v4Key, zeroForOne, slice));
        }
        out = IERC20(tokenOut).balanceOf(address(this)) - before;
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        (PoolKey memory key, bool zeroForOne, uint256 amt) = abi.decode(data, (PoolKey, bool, uint256));
        uint160 limit = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
        BalanceDelta d = poolManager.swap(key, IPoolManager.SwapParams(zeroForOne, -int256(amt), limit), "");
        if (zeroForOne) {
            uint256 owe0 = uint256(uint128(-d.amount0()));
            uint256 got1 = uint256(uint128(d.amount1()));
            poolManager.sync(key.currency0);
            IERC20(Currency.unwrap(key.currency0)).safeTransfer(address(poolManager), owe0);
            poolManager.settle();
            poolManager.take(key.currency1, address(this), got1);
            return abi.encode(got1);
        } else {
            uint256 owe1 = uint256(uint128(-d.amount1()));
            uint256 got0 = uint256(uint128(d.amount0()));
            poolManager.sync(key.currency1);
            IERC20(Currency.unwrap(key.currency1)).safeTransfer(address(poolManager), owe1);
            poolManager.settle();
            poolManager.take(key.currency0, address(this), got0);
            return abi.encode(got0);
        }
    }

    function _noRetain(address stock, uint256 u0, uint256 s0) internal view {
        if (usdg.balanceOf(address(this)) > u0) revert NotZeroAfter();
        if (IERC20(stock).balanceOf(address(this)) > s0) revert NotZeroAfter();
    }
}
