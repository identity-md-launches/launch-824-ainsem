// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {AINSEM} from "../src/AINSEM.sol";
import {LaunchFactoryMock} from "./helpers/LaunchFactoryMock.sol";

contract AINSEMTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    uint64 private constant LAUNCH_NUMBER = 42;
    address private constant MANAGER = address(0x1000);
    address private constant DISTRIBUTOR = address(0x2000);
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5000);

    LaunchFactoryMock private factory;
    AINSEM private token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        factory = new LaunchFactoryMock();
        token = factory.deploy(MANAGER, LAUNCH_NUMBER);
    }

    function test_metadataAndConstructorSupply() public view {
        assertEq(token.name(), "AINSEM");
        assertEq(token.symbol(), "AINSEM");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(factory)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.factory(), address(factory));
        assertEq(token.poolManager(), MANAGER);
        assertEq(token.launchNumber(), LAUNCH_NUMBER);
        assertEq(token.BURN_BPS(), 100);
    }

    function test_constructorEmitsWholeMint() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(this), SUPPLY);
        AINSEM direct = new AINSEM(address(this), MANAGER, 0);
        assertEq(direct.balanceOf(address(this)), SUPPLY);
    }

    function test_rejectsInvalidDeploymentParameters() public {
        vm.expectRevert(AINSEM.InvalidLaunchAddress.selector);
        new AINSEM(address(0), MANAGER, LAUNCH_NUMBER);
        vm.expectRevert(AINSEM.InvalidLaunchAddress.selector);
        new AINSEM(address(this), address(0), LAUNCH_NUMBER);
        vm.expectRevert(AINSEM.InvalidLaunchAddress.selector);
        new AINSEM(address(this), address(this), LAUNCH_NUMBER);
        vm.expectRevert(AINSEM.FactoryMustDeploy.selector);
        new AINSEM(address(factory), MANAGER, LAUNCH_NUMBER);
    }

    function test_transferBurnsOnePercentAndEmitsBothMovements() public {
        factory.move(token, ALICE, 100 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, address(0), 1 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 99 ether);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 100 ether));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 99 ether);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY - 1 ether);
    }

    function test_roundingAndZeroTransfers() public {
        factory.move(token, ALICE, 1_000);
        vm.startPrank(ALICE);
        token.transfer(BOB, 99);
        assertEq(token.balanceOf(BOB), 99);
        assertEq(token.totalSupply(), SUPPLY);
        token.transfer(BOB, 100);
        token.transfer(BOB, 101);
        assertEq(token.balanceOf(BOB), 298);
        assertEq(token.totalSupply(), SUPPLY - 2);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        token.transfer(BOB, 0);
        vm.stopPrank();
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        assertEq(token.balanceOf(ALICE), 700);
    }

    function test_selfTransferStillBurns() public {
        factory.move(token, ALICE, 100 ether);
        vm.prank(ALICE);
        token.transfer(ALICE, 100 ether);
        assertEq(token.balanceOf(ALICE), 99 ether);
        assertEq(token.totalSupply(), SUPPLY - 1 ether);
    }

    function test_transferFromUsesGrossAllowance() public {
        factory.move(token, ALICE, 200 ether);
        vm.prank(ALICE);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(ALICE, SPENDER, 150 ether);
        token.approve(SPENDER, 150 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 100 ether));
        assertEq(token.allowance(ALICE, SPENDER), 50 ether);
        assertEq(token.balanceOf(ALICE), 100 ether);
        assertEq(token.balanceOf(BOB), 99 ether);
        assertEq(token.totalSupply(), SUPPLY - 1 ether);
    }

    function test_infiniteApprovalAndRevocation() public {
        factory.move(token, ALICE, 200 ether);
        vm.prank(ALICE);
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 100 ether);
        assertEq(token.allowance(ALICE, SPENDER), type(uint256).max);
        vm.prank(ALICE);
        token.approve(SPENDER, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 1);
    }

    function test_transferFromToSelfStillBurnsAndSpendsGrossAllowance() public {
        factory.move(token, ALICE, 100 ether);
        vm.prank(ALICE);
        token.approve(SPENDER, 100 ether);
        vm.prank(SPENDER);
        token.transferFrom(ALICE, ALICE, 100 ether);
        assertEq(token.balanceOf(ALICE), 99 ether);
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY - 1 ether);
    }

    function test_insufficientBalanceIsAtomicEvenAfterAllowanceSpend() public {
        factory.move(token, ALICE, 100 ether);
        vm.prank(ALICE);
        token.approve(SPENDER, 200 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 100 ether, 101 ether)
        );
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 101 ether);
        assertEq(token.allowance(ALICE, SPENDER), 200 ether);
        assertEq(token.balanceOf(ALICE), 100 ether);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_rejectsInsufficientGrossBalanceOnSelfTransfer() public {
        factory.move(token, ALICE, 100 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 100 ether, 101 ether)
        );
        vm.prank(ALICE);
        token.transfer(ALICE, 101 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_netOnlyAllowanceCannotCoverTransfer() public {
        factory.move(token, ALICE, 100 ether);
        vm.prank(ALICE);
        token.approve(SPENDER, 99 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 99 ether, 100 ether)
        );
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 100 ether);
        assertEq(token.allowance(ALICE, SPENDER), 99 ether);
        assertEq(token.balanceOf(ALICE), 100 ether);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_rejectsZeroAddressesWithoutBurningOrSpendingAllowance() public {
        factory.move(token, ALICE, 100 ether);
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 100 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        token.approve(SPENDER, 100 ether);
        vm.stopPrank();
        vm.startPrank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(ALICE, address(0), 100 ether);
        // OpenZeppelin validates the allowance owner before reaching the transfer.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), BOB, 0);
        vm.stopPrank();
        assertEq(token.allowance(ALICE, SPENDER), 100 ether);
        assertEq(token.balanceOf(ALICE), 100 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_launchDistributionClaimsSeedBuyAndSellMoveExactAmounts() public {
        factory.register(LAUNCH_NUMBER, DISTRIBUTOR);
        uint256 swarm = SUPPLY / 10;
        uint256 seed = SUPPLY / 2;
        uint256 remainder = SUPPLY - swarm - seed;
        factory.move(token, DISTRIBUTOR, swarm);
        factory.move(token, MANAGER, seed);
        factory.move(token, ALICE, remainder);
        assertEq(token.balanceOf(DISTRIBUTOR), swarm);
        assertEq(token.balanceOf(MANAGER), seed);
        assertEq(token.balanceOf(ALICE), remainder);
        assertEq(token.balanceOf(address(factory)), 0);
        vm.prank(DISTRIBUTOR);
        token.transfer(BOB, swarm);
        assertEq(token.balanceOf(DISTRIBUTOR), 0);
        assertEq(token.balanceOf(BOB), swarm);

        // Model the token legs of PoolManager.take and trader settlement.
        vm.prank(MANAGER);
        token.transfer(ALICE, 1_000 ether);
        assertEq(token.balanceOf(ALICE), remainder + 1_000 ether);
        vm.prank(ALICE);
        token.transfer(MANAGER, 1_000 ether);
        assertEq(token.balanceOf(MANAGER), seed);
        assertEq(token.balanceOf(ALICE), remainder);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_poolSettlementThroughAllowanceIsExact() public {
        factory.move(token, ALICE, 100 ether);
        vm.prank(ALICE);
        token.approve(SPENDER, 100 ether);
        vm.prank(SPENDER);
        token.transferFrom(ALICE, MANAGER, 100 ether);
        assertEq(token.balanceOf(MANAGER), 100 ether);
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_privilegedCallersStillNeedAllowance() public {
        factory.move(token, ALICE, 100 ether);
        factory.register(LAUNCH_NUMBER, DISTRIBUTOR);
        address[3] memory callers = [address(factory), MANAGER, DISTRIBUTOR];
        for (uint256 i; i < callers.length; ++i) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, callers[i], 0, 100 ether)
            );
            vm.prank(callers[i]);
            token.transferFrom(ALICE, callers[i], 100 ether);
        }
        assertEq(token.balanceOf(ALICE), 100 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_distributorIsResolvedAfterDeploymentAndOnlyForThisLaunch() public {
        factory.move(token, DISTRIBUTOR, 300 ether);
        factory.register(LAUNCH_NUMBER + 1, DISTRIBUTOR);
        vm.prank(DISTRIBUTOR);
        token.transfer(ALICE, 100 ether);
        assertEq(token.balanceOf(ALICE), 99 ether);
        factory.register(LAUNCH_NUMBER, DISTRIBUTOR);
        vm.prank(DISTRIBUTOR);
        token.transfer(BOB, 100 ether);
        assertEq(token.balanceOf(BOB), 100 ether);
        factory.register(LAUNCH_NUMBER, address(0));
        vm.prank(DISTRIBUTOR);
        token.transfer(BOB, 100 ether);
        assertEq(token.balanceOf(BOB), 199 ether);
        assertEq(token.totalSupply(), SUPPLY - 2 ether);
    }

    function test_sendingToFactoryOrDistributorDoesNotGrantExemption() public {
        factory.register(LAUNCH_NUMBER, DISTRIBUTOR);
        factory.move(token, ALICE, 200 ether);
        uint256 factoryBalance = token.balanceOf(address(factory));
        vm.startPrank(ALICE);
        token.transfer(address(factory), 100 ether);
        token.transfer(DISTRIBUTOR, 100 ether);
        vm.stopPrank();
        assertEq(token.balanceOf(address(factory)), factoryBalance + 99 ether);
        assertEq(token.balanceOf(DISTRIBUTOR), 99 ether);
        assertEq(token.totalSupply(), SUPPLY - 2 ether);
    }

    function test_noMintOrAdministrativeBackdoors() public {
        factory.move(token, ALICE, 100 ether);
        bytes[] memory calls = new bytes[](15);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", BOB, SUPPLY);
        calls[1] = abi.encodeWithSignature("mint(uint256)", SUPPLY);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("initialize(address)", BOB);
        calls[4] = abi.encodeWithSignature("upgradeTo(address)", BOB);
        calls[5] = abi.encodeWithSignature("pause()");
        calls[6] = abi.encodeWithSignature("blacklist(address)", ALICE);
        calls[7] = abi.encodeWithSignature("freeze(address)", ALICE);
        calls[8] = abi.encodeWithSignature("seize(address)", ALICE);
        calls[9] = abi.encodeWithSignature("burnFrom(address,uint256)", ALICE, 100 ether);
        calls[10] = abi.encodeWithSignature("transferOwnership(address)", BOB);
        calls[11] = abi.encodeWithSignature("setFee(uint256)", 10_000);
        calls[12] = abi.encodeWithSignature("setMinter(address)", BOB);
        calls[13] = abi.encodeWithSignature("setExempt(address,bool)", BOB, true);
        calls[14] = abi.encodeWithSignature("burn(uint256)", 1);
        address[2] memory callers = [address(factory), BOB];
        for (uint256 i; i < callers.length; ++i) {
            for (uint256 j; j < calls.length; ++j) {
                vm.prank(callers[i]);
                (bool success,) = address(token).call(calls[j]);
                assertFalse(success);
                assertEq(token.totalSupply(), SUPPLY);
                assertEq(token.balanceOf(ALICE), 100 ether);
                assertEq(token.balanceOf(BOB), 0);
            }
        }
        vm.prank(ALICE);
        token.transfer(BOB, 100 ether);
        assertEq(token.balanceOf(BOB), 99 ether);
    }

    function test_runtimeContainsNoForbiddenOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff);
        }
    }

    function testFuzz_transferConservesBalancesAndBurn(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        factory.move(token, ALICE, amount);
        vm.prank(ALICE);
        token.transfer(BOB, amount);
        uint256 burned = amount / 100;
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), amount - burned);
        assertEq(token.totalSupply(), SUPPLY - burned);
        assertEq(token.balanceOf(address(factory)) + token.balanceOf(BOB), token.totalSupply());
    }

    function testFuzz_transferFromAndDirectTransferAgree(uint256 amount, uint256 approval) public {
        amount = bound(amount, 0, SUPPLY);
        approval = bound(approval, amount, type(uint256).max);
        factory.move(token, ALICE, amount);
        vm.prank(ALICE);
        token.approve(SPENDER, approval);
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, amount);
        assertEq(token.balanceOf(BOB), amount - amount / 100);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY - amount / 100);
        assertEq(token.allowance(ALICE, SPENDER), approval == type(uint256).max ? approval : approval - amount);
    }

    function testFuzz_rejectsOverspendingWithoutOverflow(uint256 amount) public {
        factory.move(token, ALICE, 100 ether);
        amount = bound(amount, 100 ether + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 100 ether, amount)
        );
        vm.prank(ALICE);
        token.transfer(BOB, amount);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(ALICE), 100 ether);
    }
}
