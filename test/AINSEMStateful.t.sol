// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {AINSEM} from "src/AINSEM.sol";
import {LaunchFactoryMock} from "./helpers/LaunchFactoryMock.sol";

/// @dev An independent ledger: inputs and expectations never come from token balances/allowances.
/// All recipients belong to this closed actor set, including the factory and both distributors.
contract AINSEMLedgerHandler is Test {
    uint256 public constant SUPPLY = 1_000_000_000 ether;
    uint64 public constant LAUNCH = 42;
    address public constant MANAGER = address(0x1000);

    LaunchFactoryMock public immutable factory;
    AINSEM public immutable token;
    address[7] public actors;
    address public distributor;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;
    uint256 public expectedBurned;
    uint256 public successfulMoves;
    uint256 public rejectedMoves;

    constructor() {
        factory = new LaunchFactoryMock();
        token = factory.deploy(MANAGER, LAUNCH);
        actors = [
            address(0xA11CE),
            address(0xB0B),
            address(0xCA401),
            MANAGER,
            address(0x2000),
            address(0x3000),
            address(factory)
        ];
        expectedBalance[address(factory)] = SUPPLY;
        for (uint256 i; i < 6; ++i) {
            factory.move(token, actors[i], SUPPLY / 8);
            expectedBalance[actors[i]] = SUPPLY / 8;
            expectedBalance[address(factory)] -= SUPPLY / 8;
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 amount = _amount(amountSeed, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _recordMove(from, from, to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 value, uint8 mode) external {
        uint256 allowance = mode % 3 == 0 ? 0 : mode % 3 == 1 ? type(uint256).max : value;
        _approve(_actor(ownerSeed), _actor(spenderSeed), allowance);
    }

    /// @dev Mix existing approvals, exact approvals, infinite approvals and revoked approvals.
    /// Preparing some calls here keeps successful delegated transfers frequent in random sequences.
    function transferFrom(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 amountSeed,
        uint8 approvalMode
    ) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 amount = _amount(amountSeed, expectedBalance[owner]);
        if (approvalMode % 4 == 1) _approve(owner, spender, amount);
        if (approvalMode % 4 == 2) _approve(owner, spender, type(uint256).max);
        if (approvalMode % 4 == 3) _approve(owner, spender, 0);

        uint256 allowed = expectedAllowance[owner][spender];
        if (amount > allowed) {
            _assertRejected(
                spender,
                abi.encodeCall(token.transferFrom, (owner, to, amount)),
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
            );
        } else {
            vm.prank(spender);
            assertTrue(token.transferFrom(owner, to, amount));
            if (allowed != type(uint256).max) expectedAllowance[owner][spender] -= amount;
            _recordMove(spender, owner, to, amount);
        }
    }

    /// @dev A registry update must not alter existing balances or allowances. Updates for a
    /// different launch must not change this token's exemption; unset/replace tests cache bugs.
    function changeDistributor(uint256 choice, bool otherLaunch) external {
        address next = choice % 3 == 0 ? address(0) : actors[4 + choice % 2];
        factory.register(otherLaunch ? LAUNCH + 1 : LAUNCH, next);
        if (!otherLaunch) distributor = next;
    }

    /// @dev Overspending is tested with and without an allowance, including self-transfers.
    /// A successful approval before a failed transfer must survive; the transfer's debit must not.
    function overdraw(uint256 ownerSeed, uint256 toSeed, uint256 excessSeed, bool delegated) external {
        address owner = _actor(ownerSeed);
        address to = _actor(toSeed);
        uint256 balance = expectedBalance[owner];
        uint256 amount = bound(excessSeed, balance + 1, type(uint256).max);
        bytes memory error =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount);
        if (delegated) {
            address spender = _actor(toSeed % actors.length + 1);
            _approve(owner, spender, amount);
            _assertRejected(spender, abi.encodeCall(token.transferFrom, (owner, to, amount)), error);
        } else {
            _assertRejected(owner, abi.encodeCall(token.transfer, (to, amount)), error);
        }
    }

    function zeroRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, bool delegated) external {
        address owner = _actor(ownerSeed);
        uint256 amount = _amount(amountSeed, expectedBalance[owner]);
        bytes memory error = abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0));
        if (delegated) {
            address spender = _actor(spenderSeed);
            _approve(owner, spender, amount);
            _assertRejected(spender, abi.encodeCall(token.transferFrom, (owner, address(0), amount)), error);
        } else {
            _assertRejected(owner, abi.encodeCall(token.transfer, (address(0), amount)), error);
        }
    }

    function _actor(uint256 seed) private view returns (address) {
        return actors[seed % actors.length];
    }

    function _amount(uint256 seed, uint256 maximum) private pure returns (uint256) {
        // Explicitly visit full balances and both sides of the first rounding threshold.
        uint256 mode = seed % 8;
        if (mode == 0) return maximum;
        uint256 amount = mode == 1 ? 0 : mode == 2 ? 1 : mode == 3 ? 99 : mode == 4 ? 100 : mode == 5 ? 101 : seed;
        return bound(amount, 0, maximum);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function _assertRejected(address caller, bytes memory data, bytes memory error) private {
        vm.prank(caller);
        (bool success, bytes memory result) = address(token).call(data);
        assertFalse(success, "invalid transfer succeeded");
        assertEq(result, error, "unexpected failure reason");
        ++rejectedMoves;
        // No ledger update: the invariant checks every balance and allowance for rollback.
    }

    function _recordMove(address caller, address from, address to, uint256 amount) private {
        // The accepted launch exceptions are caller=factory, pool settlement, and current claims.
        bool settlement = caller == address(factory) || caller == MANAGER || from == MANAGER || to == MANAGER;
        bool claim = distributor != address(0) && (caller == distributor || from == distributor);
        // Basis-point oracle is safe because all generated successful debits are <= initial supply.
        uint256 burn = settlement || claim ? 0 : amount * 100 / 10_000;
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount - burn;
        expectedBurned += burn;
        ++successfulMoves;
    }
}

contract AINSEMStatefulTest is StdInvariant, Test {
    AINSEMLedgerHandler private handler;
    AINSEM private token;

    function setUp() public {
        handler = new AINSEMLedgerHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        selectors[3] = handler.changeDistributor.selector;
        selectors[4] = handler.overdraw.selector;
        selectors[5] = handler.zeroRecipient.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_eachBalanceAndAllowanceMatchesTheLedger() public view {
        uint256 sum;
        for (uint256 i; i < 7; ++i) {
            address owner = handler.actors(i);
            uint256 balance = token.balanceOf(owner);
            assertEq(balance, handler.expectedBalance(owner), "incorrect individual balance");
            sum += balance;
            for (uint256 j; j < 7; ++j) {
                address spender = handler.actors(j);
                assertEq(
                    token.allowance(owner, spender), handler.expectedAllowance(owner, spender), "incorrect allowance"
                );
            }
        }
        assertEq(sum, token.totalSupply(), "unaccounted tokens");
        assertEq(token.totalSupply() + handler.expectedBurned(), handler.SUPPLY(), "mint or incorrect burn");
        assertEq(token.balanceOf(address(0)), 0, "burn credited zero address");
    }

    /// @dev Fixed replay guarantees the handler's success, failure, rotation, and revocation paths
    /// are exercised even independently of a particular invariant seed.
    function test_sequenceBurnClaimRotateRevokeAndFail() public {
        handler.transfer(0, 1, 100);
        invariant_eachBalanceAndAllowanceMatchesTheLedger();
        handler.changeDistributor(2, false); // actor 4 becomes the distributor
        handler.transferFrom(0, 4, 1, 100, 1);
        invariant_eachBalanceAndAllowanceMatchesTheLedger();
        handler.changeDistributor(1, false); // actor 5 replaces actor 4
        handler.transferFrom(0, 4, 1, 100, 2);
        invariant_eachBalanceAndAllowanceMatchesTheLedger();
        handler.approve(0, 4, 0, 0);
        handler.transferFrom(0, 4, 1, 100, 0);
        handler.overdraw(0, 0, type(uint256).max, true);
        handler.zeroRecipient(0, 4, 100, true);
        handler.changeDistributor(2, true);
        invariant_eachBalanceAndAllowanceMatchesTheLedger();
        assertEq(handler.successfulMoves(), 3);
        assertEq(handler.rejectedMoves(), 3);
        assertEq(handler.expectedBurned(), 2);
    }
}
