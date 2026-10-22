// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MADToken} from "../src/MADToken.sol";

/// @notice Deploys the token and pays out the launch split in a single call, the way the factory does
///         in one transaction, so nothing depends on state surviving between top-level calls.
contract LaunchLike {
    MADToken public immutable token;

    constructor(address distributor, address pool, address remainder) {
        token = new MADToken();
        uint256 supply = token.totalSupply();
        uint256 swarm = supply / 10;
        uint256 seed = (supply * 8_000) / 10_000;
        require(token.transfer(distributor, swarm), "swarm");
        require(token.transfer(pool, seed), "seed");
        require(token.transfer(remainder, token.balanceOf(address(this))), "remainder");
    }
}

contract MADTokenEdgeTest is Test {
    uint256 constant SUPPLY = 1_000_000_000 ether;

    MADToken token;
    address deployer = makeAddr("deployer");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        vm.prank(deployer);
        token = new MADToken();
    }

    // ----------------------------------------------------------------- deployment

    function test_twoDeploymentsAreIndependent() public {
        vm.prank(alice);
        MADToken other = new MADToken();
        assertEq(other.balanceOf(alice), SUPPLY);
        assertEq(other.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply() + other.totalSupply(), 2 * SUPPLY);
    }

    function test_launchSplitInOneTransactionArrivesExactly() public {
        address distributor = makeAddr("distributor");
        address pool = makeAddr("pool");
        address remainder = makeAddr("remainder");
        LaunchLike launch = new LaunchLike(distributor, pool, remainder);
        MADToken t = launch.token();
        assertEq(t.balanceOf(distributor), 100_000_000 ether);
        assertEq(t.balanceOf(pool), 800_000_000 ether);
        assertEq(t.balanceOf(remainder), 100_000_000 ether);
        assertEq(t.balanceOf(address(launch)), 0);
        assertEq(t.totalSupply(), SUPPLY);
    }

    function test_constructorEmitsExactlyOneEvent() public {
        vm.recordLogs();
        vm.prank(alice);
        new MADToken();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], IERC20.Transfer.selector);
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(alice))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    // ----------------------------------------------------------------- transfer edges

    function test_transferOneWei() public {
        vm.prank(deployer);
        assertTrue(token.transfer(alice, 1));
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
    }

    function test_transferMaxUintReverts() public {
        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, type(uint256).max)
        );
        token.transfer(alice, type(uint256).max);
    }

    function test_transferZeroToZeroAddressStillReverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
    }

    function test_transferZeroEmitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(alice, bob, 0);
        vm.prank(alice);
        token.transfer(bob, 0);
    }

    function test_selfTransferOverBalanceReverts() public {
        vm.prank(deployer);
        token.transfer(alice, 5);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 5, 6));
        token.transfer(alice, 6);
        assertEq(token.balanceOf(alice), 5);
    }

    function test_transferToTokenContractIsJustABalance() public {
        vm.prank(deployer);
        token.transfer(address(token), 1 ether);
        assertEq(token.balanceOf(address(token)), 1 ether);
        assertEq(token.totalSupply(), SUPPLY, "tokens sent to the contract are not burned");
    }

    function test_failedTransferLeavesStateUntouched() public {
        vm.prank(deployer);
        token.transfer(alice, 10);
        vm.prank(alice);
        (bool ok,) = address(token).call(abi.encodeCall(IERC20.transfer, (bob, 11)));
        assertFalse(ok);
        assertEq(token.balanceOf(alice), 10);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    // ----------------------------------------------------------------- approvals and transferFrom edges

    function test_approveOverwritesRatherThanAdds() public {
        vm.startPrank(deployer);
        token.approve(alice, 100);
        token.approve(alice, 40);
        vm.stopPrank();
        assertEq(token.allowance(deployer, alice), 40);
    }

    function test_approveZeroRevokes() public {
        vm.prank(deployer);
        token.approve(alice, 100);
        vm.prank(deployer);
        token.approve(alice, 0);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        token.transferFrom(deployer, bob, 1);
    }

    function test_approveMoreThanBalanceIsAllowedButCannotOverdraw() public {
        vm.prank(alice);
        token.approve(bob, SUPPLY * 10);
        assertEq(token.allowance(alice, bob), SUPPLY * 10);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, bob), SUPPLY * 10, "failed pull consumed allowance");
    }

    function test_allowanceSpentExactlyToZero() public {
        vm.prank(deployer);
        token.approve(alice, 7);
        vm.prank(alice);
        token.transferFrom(deployer, bob, 7);
        assertEq(token.allowance(deployer, alice), 0);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        token.transferFrom(deployer, bob, 1);
    }

    function test_maxMinusOneAllowanceIsDecremented() public {
        vm.prank(deployer);
        token.approve(alice, type(uint256).max - 1);
        vm.prank(alice);
        token.transferFrom(deployer, bob, 1 ether);
        assertEq(token.allowance(deployer, alice), type(uint256).max - 1 - 1 ether);
    }

    function test_selfSpendStillNeedsAllowance() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        token.transferFrom(deployer, alice, 1);
    }

    function test_transferFromToZeroRevertsAndKeepsAllowance() public {
        vm.prank(deployer);
        token.approve(alice, 100);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(deployer, address(0), 50);
        assertEq(token.allowance(deployer, alice), 100);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_transferFromZeroAddressOwnerReverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        token.transferFrom(address(0), bob, 1);
    }

    function test_allowanceIsPerSpender() public {
        vm.prank(deployer);
        token.approve(alice, 100);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        token.transferFrom(deployer, bob, 1);
        assertEq(token.allowance(deployer, alice), 100);
        assertEq(token.allowance(deployer, bob), 0);
    }

    function test_allowanceIsDirectional() public {
        vm.prank(deployer);
        token.approve(alice, 100);
        assertEq(token.allowance(alice, deployer), 0);
    }

    function test_transferFromDoesNotEmitApproval() public {
        vm.prank(deployer);
        token.approve(alice, 100);
        vm.recordLogs();
        vm.prank(alice);
        token.transferFrom(deployer, bob, 30);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], IERC20.Transfer.selector);
    }

    // ----------------------------------------------------------------- fuzz

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_strangerCannotPullWithoutAllowance(address stranger, uint256 amount) public {
        vm.assume(stranger != deployer);
        amount = bound(amount, 1, SUPPLY);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, stranger, 0, amount));
        token.transferFrom(deployer, stranger, amount);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_approveSetsExactAllowance(address spender, uint256 amount) public {
        vm.assume(spender != address(0));
        vm.prank(alice);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(alice, spender), amount);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_transferFromConservesAndDecrements(uint256 approved, uint256 amount, uint256 held) public {
        held = bound(held, 0, SUPPLY);
        approved = bound(approved, 0, type(uint256).max - 1);
        amount = bound(amount, 0, approved < held ? approved : held);
        vm.prank(deployer);
        token.transfer(alice, held);
        vm.prank(alice);
        token.approve(bob, approved);

        vm.prank(bob);
        assertTrue(token.transferFrom(alice, deployer, amount));
        assertEq(token.balanceOf(alice), held - amount);
        assertEq(token.balanceOf(deployer), SUPPLY - held + amount);
        assertEq(token.allowance(alice, bob), approved - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_transferFromAboveBalanceRevertsWithInfiniteAllowance(uint256 held, uint256 amount) public {
        held = bound(held, 0, SUPPLY);
        amount = bound(amount, held + 1, type(uint256).max);
        vm.prank(deployer);
        token.transfer(alice, held);
        vm.prank(alice);
        token.approve(bob, type(uint256).max);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, amount));
        token.transferFrom(alice, bob, amount);
        assertEq(token.balanceOf(alice), held);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_unknownCalldataReverts(bytes calldata data, address caller) public {
        vm.assume(data.length >= 4);
        bytes4 sel = bytes4(data[:4]);
        vm.assume(
            sel != IERC20.transfer.selector && sel != IERC20.approve.selector && sel != IERC20.transferFrom.selector
                && sel != IERC20.balanceOf.selector && sel != IERC20.allowance.selector
                && sel != IERC20.totalSupply.selector && sel != token.name.selector && sel != token.symbol.selector
                && sel != token.decimals.selector && sel != token.TOKEN_NAME.selector
                && sel != token.TOKEN_SYMBOL.selector && sel != token.TOKEN_DECIMALS.selector
                && sel != token.TOTAL_SUPPLY.selector
        );
        vm.prank(caller);
        (bool ok,) = address(token).call(data);
        assertFalse(ok);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }
}
