// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {AINSEM} from "../src/AINSEM.sol";
import {LaunchFactoryMock} from "./helpers/LaunchFactoryMock.sol";

contract TokenHandler is Test {
    AINSEM public immutable token;
    address[5] public actors = [address(0xA11CE), address(0xB0B), address(0xCA401), address(0x1000), address(0x2000)];
    uint256 public burned;

    constructor(AINSEM token_) {
        token = token_;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, token.balanceOf(from));
        uint256 beforeSupply = token.totalSupply();
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        burned += _burn(from, from, to, amount);
        assertLe(token.totalSupply(), beforeSupply);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address spender = actors[spenderSeed % actors.length];
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);
        uint256 allowanceBefore = token.allowance(from, spender);
        uint256 beforeSupply = token.totalSupply();
        amount = bound(amount, 0, fromBefore);
        vm.prank(spender);
        (bool success, bytes memory result) =
            address(token).call(abi.encodeCall(token.transferFrom, (from, to, amount)));
        if (amount > allowanceBefore) {
            assertFalse(success);
            assertEq(token.balanceOf(from), fromBefore);
            assertEq(token.balanceOf(to), toBefore);
            assertEq(token.allowance(from, spender), allowanceBefore);
            assertEq(token.totalSupply(), beforeSupply);
        } else {
            assertTrue(success);
            assertTrue(abi.decode(result, (bool)));
            burned += _burn(spender, from, to, amount);
            assertEq(
                token.allowance(from, spender),
                allowanceBefore == type(uint256).max ? allowanceBefore : allowanceBefore - amount
            );
            assertLe(token.totalSupply(), beforeSupply);
        }
    }

    function _burn(address caller, address from, address to, uint256 amount) private view returns (uint256) {
        if (caller == actors[3] || caller == actors[4] || from == actors[3] || from == actors[4] || to == actors[3]) {
            return 0;
        }
        return amount / 100;
    }
}

contract AINSEMInvariantTest is StdInvariant, Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    LaunchFactoryMock private factory;
    AINSEM private token;
    TokenHandler private handler;

    function setUp() public {
        factory = new LaunchFactoryMock();
        token = factory.deploy(address(0x1000), 42);
        factory.register(42, address(0x2000));
        handler = new TokenHandler(token);
        for (uint256 i; i < 5; ++i) {
            factory.move(token, handler.actors(i), SUPPLY / 5);
        }
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_balancesEqualSupplyAndBurnsAccountForEveryMissingToken() public view {
        uint256 sum;
        for (uint256 i; i < 5; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(sum, token.totalSupply());
        assertEq(token.totalSupply() + handler.burned(), SUPPLY);
        assertLe(token.totalSupply(), SUPPLY);
    }
}
