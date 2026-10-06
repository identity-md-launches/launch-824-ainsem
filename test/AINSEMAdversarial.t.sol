// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {AINSEM} from "src/AINSEM.sol";
import {LaunchFactoryMock} from "./helpers/LaunchFactoryMock.sol";

contract AINSEMAdversarialTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0xCA401);
    address private constant MANAGER = address(0x1000);
    address private constant DISTRIBUTOR = address(0x2000);
    LaunchFactoryMock private factory;
    AINSEM private token;

    event Transfer(address indexed from, address indexed to, uint256 amount);

    function setUp() public {
        factory = new LaunchFactoryMock();
        token = factory.deploy(MANAGER, 42);
    }

    function test_oneBaseUnitCanEmptyAnAccount() public {
        factory.move(token, ALICE, 1);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 1);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 1));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_fullSupplyRoundTripDestroysOnlyTheTwoBurns() public {
        factory.move(token, ALICE, SUPPLY);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, SUPPLY));
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 990_000_000 ether);
        assertEq(token.totalSupply(), 990_000_000 ether);

        vm.prank(BOB);
        assertTrue(token.transfer(ALICE, 990_000_000 ether));
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(ALICE), 980_100_000 ether);
        assertEq(token.totalSupply(), 980_100_000 ether);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function test_maximumDelegatedTransferCannotOverflowOrSpendInfiniteApproval() public {
        factory.move(token, ALICE, SUPPLY);
        vm.prank(ALICE);
        token.approve(SPENDER, type(uint256).max);
        address[2] memory recipients = [ALICE, BOB];
        for (uint256 i; i < recipients.length; ++i) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, SUPPLY, type(uint256).max)
            );
            vm.prank(SPENDER);
            token.transferFrom(ALICE, recipients[i], type(uint256).max);
            assertEq(token.allowance(ALICE, SPENDER), type(uint256).max);
            assertEq(token.balanceOf(ALICE), SUPPLY);
            assertEq(token.balanceOf(BOB), 0);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }

    function test_replacedApprovalIsNotAddedAndSpentApprovalCannotBeReplayed() public {
        factory.move(token, ALICE, 300 ether);
        vm.startPrank(ALICE);
        token.approve(SPENDER, 200 ether);
        token.approve(SPENDER, 100 ether);
        vm.stopPrank();
        assertEq(token.allowance(ALICE, SPENDER), 100 ether);
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 100 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 100 ether));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 100 ether);
        assertEq(token.balanceOf(ALICE), 200 ether);
        assertEq(token.balanceOf(BOB), 99 ether);
        assertEq(token.totalSupply(), SUPPLY - 1 ether);
        assertEq(token.allowance(ALICE, SPENDER), 0);
    }

    function test_distributorRotationAppliesToExistingAllowancesImmediately() public {
        factory.move(token, ALICE, 300 ether);
        vm.prank(ALICE);
        token.approve(DISTRIBUTOR, type(uint256).max);
        factory.register(42, DISTRIBUTOR);
        vm.prank(DISTRIBUTOR);
        token.transferFrom(ALICE, BOB, 100 ether);
        assertEq(token.balanceOf(BOB), 100 ether);

        factory.register(42, SPENDER);
        vm.prank(DISTRIBUTOR);
        token.transferFrom(ALICE, BOB, 100 ether);
        assertEq(token.balanceOf(BOB), 199 ether);

        factory.register(42, address(0));
        vm.prank(DISTRIBUTOR);
        token.transferFrom(ALICE, BOB, 100 ether);
        assertEq(token.balanceOf(BOB), 298 ether);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.allowance(ALICE, DISTRIBUTOR), type(uint256).max);
        assertEq(token.totalSupply(), SUPPLY - 2 ether);
    }

    function test_twoLaunchesCannotBorrowEachOthersDistributorExemption() public {
        // The largest launch key also catches accidental narrowing in the registry request.
        AINSEM other = factory.deploy(MANAGER, type(uint64).max);
        factory.register(42, DISTRIBUTOR);
        factory.register(type(uint64).max, SPENDER);
        factory.move(token, DISTRIBUTOR, 100 ether);
        factory.move(other, DISTRIBUTOR, 100 ether);
        factory.move(token, SPENDER, 100 ether);
        factory.move(other, SPENDER, 100 ether);
        vm.startPrank(DISTRIBUTOR);
        token.transfer(BOB, 100 ether);
        other.transfer(BOB, 100 ether);
        vm.stopPrank();
        vm.startPrank(SPENDER);
        token.transfer(ALICE, 100 ether);
        other.transfer(ALICE, 100 ether);
        vm.stopPrank();
        assertEq(token.balanceOf(BOB), 100 ether);
        assertEq(other.balanceOf(BOB), 99 ether);
        assertEq(token.balanceOf(ALICE), 99 ether);
        assertEq(other.balanceOf(ALICE), 100 ether);
        assertEq(token.totalSupply(), SUPPLY - 1 ether);
        assertEq(other.totalSupply(), SUPPLY - 1 ether);
        assertEq(other.launchNumber(), type(uint64).max);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_directAndDelegatedTransferAreEquivalent(
        uint256 amount,
        uint256 recipientBalance,
        bool selfTransfer,
        bool infiniteApproval
    ) public {
        amount = bound(amount, 0, SUPPLY);
        recipientBalance = bound(recipientBalance, 0, SUPPLY - amount);
        factory.move(token, ALICE, amount);
        factory.move(token, BOB, recipientBalance);
        address recipient = selfTransfer ? ALICE : BOB;
        uint256 snapshot = vm.snapshotState();
        vm.prank(ALICE);
        assertTrue(token.transfer(recipient, amount));
        uint256 directAlice = token.balanceOf(ALICE);
        uint256 directBob = token.balanceOf(BOB);
        uint256 directSupply = token.totalSupply();

        assertTrue(vm.revertToState(snapshot));
        uint256 approval = infiniteApproval ? type(uint256).max : amount;
        vm.prank(ALICE);
        token.approve(SPENDER, approval);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, recipient, amount));
        assertEq(token.balanceOf(ALICE), directAlice);
        assertEq(token.balanceOf(BOB), directBob);
        assertEq(token.totalSupply(), directSupply);
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.allowance(ALICE, SPENDER), infiniteApproval ? type(uint256).max : 0);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_rejectedOverspendPreservesAllowanceForAValidRetry(
        uint256 balance,
        uint256 excess,
        bool selfTransfer
    ) public {
        balance = bound(balance, 1, SUPPLY);
        uint256 requested = bound(excess, balance + 1, type(uint256).max);
        address recipient = selfTransfer ? ALICE : BOB;
        factory.move(token, ALICE, balance);
        vm.prank(ALICE);
        token.approve(SPENDER, requested);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, balance, requested)
        );
        vm.prank(SPENDER);
        token.transferFrom(ALICE, recipient, requested);
        assertEq(token.allowance(ALICE, SPENDER), requested);
        assertEq(token.balanceOf(ALICE), balance);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);

        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, recipient, balance));
        assertEq(token.balanceOf(recipient), balance - balance / 100);
        assertEq(token.balanceOf(selfTransfer ? BOB : ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY - balance / 100);
        assertEq(token.allowance(ALICE, SPENDER), requested == type(uint256).max ? requested : requested - balance);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_burnStaysWithinOneBaseUnitOfOnePercent(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        factory.move(token, ALICE, amount);
        vm.prank(ALICE);
        token.transfer(BOB, amount);
        uint256 burned = SUPPLY - token.totalSupply();
        // Characterize floor rounding by inequalities, independently of the division formula.
        assertLe(burned * 100, amount);
        assertLt(amount, (burned + 1) * 100);
        assertEq(token.balanceOf(BOB) + burned, amount);
        assertEq(token.balanceOf(ALICE), 0);
    }
}
