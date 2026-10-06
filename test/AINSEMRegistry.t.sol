// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {AINSEM, ILaunchFactory} from "../src/AINSEM.sol";
import {LaunchFactoryMock} from "./helpers/LaunchFactoryMock.sol";

contract OversizedRegistry {
    fallback() external {
        assembly ("memory-safe") {
            let output := mload(0x40)
            return(output, 32768)
        }
    }
}

contract ReentrantRegistry {
    AINSEM private immutable token;

    constructor(AINSEM token_) {
        token = token_;
    }

    function distributorOf(uint64) external returns (address) {
        // Even the registry's own balance cannot be moved during a STATICCALL.
        token.transfer(address(0xBAD), 100 ether);
        return address(0xBAD);
    }
}

contract AINSEMRegistryTest is Test {
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant MANAGER = address(0x1000);
    uint64 private constant LAUNCH_NUMBER = 42;
    uint256 private constant SUPPLY = 1_000_000_000 ether;

    LaunchFactoryMock private factory;
    AINSEM private token;

    function setUp() public {
        factory = new LaunchFactoryMock();
        token = factory.deploy(MANAGER, LAUNCH_NUMBER);
        factory.move(token, ALICE, 100 ether);
    }

    function test_revertingLookupDoesNotFreezeHolders() public {
        vm.mockCallRevert(
            address(factory),
            abi.encodeCall(ILaunchFactory.distributorOf, (LAUNCH_NUMBER)),
            bytes("registry unavailable")
        );
        _assertOrdinaryTransfer();
    }

    function test_emptyReturnDoesNotFreezeHolders() public {
        _mockResponse("");
        _assertOrdinaryTransfer();
    }

    function test_shortReturnDoesNotFreezeHolders() public {
        _mockResponse(hex"01");
        _assertOrdinaryTransfer();
    }

    function test_longReturnDoesNotFreezeHolders() public {
        _mockResponse(abi.encode(ALICE, BOB));
        _assertOrdinaryTransfer();
    }

    function test_noncanonicalAddressDoesNotGrantExemption() public {
        _mockResponse(abi.encode((uint256(1) << 160) | uint160(ALICE)));
        _assertOrdinaryTransfer();
    }

    function test_gasExhaustingRegistryDoesNotFreezeHolders() public {
        // JUMPDEST; PUSH1 0; JUMP: exhausts only the lookup's gas allowance.
        vm.etch(address(factory), hex"5b600056");
        _assertOrdinaryTransfer();
    }

    function test_excessiveReturnDataDoesNotFreezeHolders() public {
        vm.etch(address(factory), address(new OversizedRegistry()).code);
        _assertOrdinaryTransfer();
    }

    function test_registryCannotReenterToChangeBalances() public {
        uint256 factoryBalance = token.balanceOf(address(factory));
        vm.etch(address(factory), address(new ReentrantRegistry(token)).code);
        _assertOrdinaryTransfer();
        assertEq(token.balanceOf(address(factory)), factoryBalance);
        assertEq(token.balanceOf(address(0xBAD)), 0);
    }

    function test_exemptPoolFlowsDoNotDependOnRegistryAvailability() public {
        vm.etch(address(factory), hex"5b600056");
        vm.prank(ALICE);
        token.transfer(MANAGER, 100 ether);
        vm.prank(MANAGER);
        token.transfer(BOB, 100 ether);
        assertEq(token.balanceOf(BOB), 100 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_eoaDeployerWithoutRegistryStillSupportsOrdinaryTransfers() public {
        vm.prank(ALICE);
        AINSEM direct = new AINSEM(ALICE, MANAGER, 0);
        assertEq(direct.balanceOf(ALICE), SUPPLY);
        vm.prank(ALICE);
        direct.transfer(BOB, 100 ether);
        vm.prank(BOB);
        direct.transfer(ALICE, 100 ether);
        assertEq(direct.balanceOf(ALICE), SUPPLY - 1 ether);
        assertEq(direct.balanceOf(BOB), 0);
        assertEq(direct.totalSupply(), SUPPLY - 1 ether);
    }

    function _mockResponse(bytes memory response) private {
        vm.mockCall(address(factory), abi.encodeCall(ILaunchFactory.distributorOf, (LAUNCH_NUMBER)), response);
    }

    function _assertOrdinaryTransfer() private {
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 100 ether));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 99 ether);
        assertEq(token.totalSupply(), SUPPLY - 1 ether);
    }
}
