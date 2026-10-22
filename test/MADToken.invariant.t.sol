// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MADToken} from "../src/MADToken.sol";

/// @notice Drives the token with random transfers, approvals and transferFroms among a closed set of
///         actors, and keeps an independent model (ghost balances and allowances) of what the token
///         should hold. Calls that must fail are made too, and must revert with the right error and
///         leave every balance and allowance untouched.
contract MADHandler is Test {
    MADToken public immutable token;
    uint256 public immutable supply;

    address[] public actors;
    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;
    /// @dev Total ever approved by owner to spender (finite approvals) and total ever pulled.
    mapping(address => mapping(address => uint256)) public ghostApprovedSum;
    mapping(address => mapping(address => uint256)) public ghostPulledSum;
    mapping(address => mapping(address => bool)) public everInfinite;

    uint256 public ghostReceivedTotal;
    uint256 public ghostSentTotal;
    uint256 public successfulCalls;
    uint256 public expectedReverts;

    constructor(MADToken token_, address[] memory actors_) {
        token = token_;
        supply = token_.totalSupply();
        actors = actors_;
        for (uint256 i; i < actors_.length; ++i) {
            ghostBalance[actors_[i]] = token_.balanceOf(actors_[i]);
        }
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    // ------------------------------------------------------------------ successful paths

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        amount = bound(amount, 0, ghostBalance[from]);

        vm.prank(from);
        assertTrue(token.transfer(to, amount), "transfer returned false");

        ghostBalance[from] -= amount;
        ghostBalance[to] += amount;
        if (from != to) {
            ghostSentTotal += amount;
            ghostReceivedTotal += amount;
        }
        successfulCalls++;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool infinite) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        amount = infinite ? type(uint256).max : bound(amount, 0, supply * 2);

        vm.prank(owner);
        assertTrue(token.approve(spender, amount), "approve returned false");

        ghostAllowance[owner][spender] = amount;
        if (infinite) everInfinite[owner][spender] = true;
        else ghostApprovedSum[owner][spender] += amount;
        successfulCalls++;
    }

    function transferFrom(uint256 spenderSeed, uint256 ownerSeed, uint256 toSeed, uint256 amount) external {
        address spender = _actor(spenderSeed);
        address owner = _actor(ownerSeed);
        address to = _actor(toSeed);
        uint256 allowed = ghostAllowance[owner][spender];
        uint256 cap = allowed < ghostBalance[owner] ? allowed : ghostBalance[owner];
        amount = bound(amount, 0, cap);

        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount), "transferFrom returned false");

        if (allowed != type(uint256).max) ghostAllowance[owner][spender] = allowed - amount;
        ghostBalance[owner] -= amount;
        ghostBalance[to] += amount;
        ghostPulledSum[owner][spender] += amount;
        successfulCalls++;
    }

    // ------------------------------------------------------------------ paths that must fail

    function transferOverBalance(uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 held = ghostBalance[from];
        uint256 amount = held + bound(excess, 1, type(uint256).max - held);

        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, amount));
        token.transfer(to, amount);
        expectedReverts++;
    }

    function transferToZero(uint256 fromSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        amount = bound(amount, 0, ghostBalance[from]);

        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), amount);
        expectedReverts++;
    }

    function transferFromOverAllowance(uint256 spenderSeed, uint256 ownerSeed, uint256 toSeed, uint256 excess)
        external
    {
        address spender = _actor(spenderSeed);
        address owner = _actor(ownerSeed);
        address to = _actor(toSeed);
        uint256 allowed = ghostAllowance[owner][spender];
        if (allowed == type(uint256).max) return; // an infinite allowance cannot be exceeded
        uint256 amount = allowed + bound(excess, 1, type(uint256).max - allowed);

        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
        );
        token.transferFrom(owner, to, amount);
        expectedReverts++;
    }

    function transferFromOverBalance(uint256 spenderSeed, uint256 ownerSeed, uint256 toSeed, uint256 excess) external {
        address spender = _actor(spenderSeed);
        address owner = _actor(ownerSeed);
        address to = _actor(toSeed);
        uint256 held = ghostBalance[owner];
        uint256 allowed = ghostAllowance[owner][spender];
        uint256 amount = held + bound(excess, 1, type(uint256).max - held);
        // Allowance is checked first; make sure this call reaches the balance check.
        if (amount > allowed) return;

        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, held, amount));
        token.transferFrom(owner, to, amount);
        expectedReverts++;
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), amount);
        expectedReverts++;
    }

    function transferFromToZero(uint256 spenderSeed, uint256 ownerSeed, uint256 amount) external {
        address spender = _actor(spenderSeed);
        address owner = _actor(ownerSeed);
        uint256 allowed = ghostAllowance[owner][spender];
        uint256 cap = allowed < ghostBalance[owner] ? allowed : ghostBalance[owner];
        amount = bound(amount, 0, cap);

        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(owner, address(0), amount);
        expectedReverts++;
    }

    /// @dev Unknown selectors (admin calls a launch floor probes) from any actor must revert and change nothing.
    function callUnknownSelector(uint256 callerSeed, bytes4 selector, uint256 arg) external {
        // Skip the real ERC-20 surface so this only exercises the fallback path.
        if (
            selector == token.transfer.selector || selector == token.approve.selector
                || selector == token.transferFrom.selector || selector == token.balanceOf.selector
                || selector == token.allowance.selector || selector == token.totalSupply.selector
                || selector == token.name.selector || selector == token.symbol.selector
                || selector == token.decimals.selector || selector == token.TOKEN_NAME.selector
                || selector == token.TOKEN_SYMBOL.selector || selector == token.TOKEN_DECIMALS.selector
                || selector == token.TOTAL_SUPPLY.selector
        ) return;
        address caller = _actor(callerSeed);
        vm.prank(caller);
        (bool ok,) = address(token).call(abi.encodeWithSelector(selector, caller, arg));
        assertFalse(ok, "unknown selector succeeded");
        expectedReverts++;
    }
}

contract MADTokenInvariantTest is Test {
    uint256 constant SUPPLY = 1_000_000_000 ether;

    MADToken token;
    MADHandler handler;
    address[] actors;

    function setUp() public {
        address deployer = makeAddr("deployer");
        actors.push(deployer);
        actors.push(makeAddr("alice"));
        actors.push(makeAddr("bob"));
        actors.push(makeAddr("carol"));
        actors.push(makeAddr("dave"));

        vm.prank(deployer);
        token = new MADToken();
        handler = new MADHandler(token, actors);

        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = MADHandler.transfer.selector;
        selectors[1] = MADHandler.approve.selector;
        selectors[2] = MADHandler.transferFrom.selector;
        selectors[3] = MADHandler.transferOverBalance.selector;
        selectors[4] = MADHandler.transferToZero.selector;
        selectors[5] = MADHandler.transferFromOverAllowance.selector;
        selectors[6] = MADHandler.transferFromOverBalance.selector;
        selectors[7] = MADHandler.approveZeroSpender.selector;
        selectors[8] = MADHandler.transferFromToZero.selector;
        selectors[9] = MADHandler.callUnknownSelector.selector;
        selectors[10] = MADHandler.transfer.selector; // weight the main flow
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_supplyNeverChanges() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.TOTAL_SUPPLY(), SUPPLY);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_actorBalancesSumToSupply() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            sum += token.balanceOf(actors[i]);
        }
        assertEq(sum, token.totalSupply(), "tokens leaked outside the actor set");
        assertEq(token.balanceOf(address(0)), 0, "zero address holds tokens");
        assertEq(token.balanceOf(address(token)), 0, "token holds itself");
        assertEq(token.balanceOf(address(handler)), 0, "handler holds tokens");
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_balancesMatchModel() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.balanceOf(actors[i]), handler.ghostBalance(actors[i]), "balance diverged from model");
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_allowancesMatchModel() public view {
        for (uint256 i; i < actors.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                assertEq(
                    token.allowance(actors[i], actors[j]),
                    handler.ghostAllowance(actors[i], actors[j]),
                    "allowance diverged from model"
                );
            }
        }
    }

    /// @dev Nobody pulls more from an owner than that owner ever approved them, unless the owner once
    ///      granted an infinite allowance.
    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_spendersNeverPullMoreThanApproved() public view {
        for (uint256 i; i < actors.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                if (handler.everInfinite(actors[i], actors[j])) continue;
                assertLe(
                    handler.ghostPulledSum(actors[i], actors[j]),
                    handler.ghostApprovedSum(actors[i], actors[j]),
                    "spender pulled more than approved"
                );
            }
        }
    }

    /// @dev The token never holds ETH and the contract has no code path that could change it.
    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_metadataIsFixed() public view {
        assertEq(token.name(), "Mutually Assured Destruction");
        assertEq(token.symbol(), "MAD");
        assertEq(token.decimals(), 18);
        assertEq(address(token).balance, 0);
    }
}
