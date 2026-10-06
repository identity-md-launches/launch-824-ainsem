// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface ILaunchFactory {
    function distributorOf(uint64 launchNumber) external view returns (address);
}

/// @title AINSEM
/// @notice One billion tokens minted once; ordinary transfers burn one percent.
/// @dev Launch settlement and claims are exempt so their recipients receive exact amounts.
contract AINSEM is ERC20 {
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;
    uint256 public constant BURN_BPS = 100;
    uint256 private constant DISTRIBUTOR_LOOKUP_GAS = 30_000;

    address public immutable factory;
    address public immutable poolManager;
    uint64 public immutable launchNumber;

    error InvalidLaunchAddress();
    error FactoryMustDeploy();

    /// @param factory_ The deploying ProjectFactory, resolved from $factory.
    /// @param poolManager_ The settlement contract, resolved from $poolManager.
    /// @param launchNumber_ The registry key, resolved from $launchNumber.
    constructor(address factory_, address poolManager_, uint64 launchNumber_) ERC20("AINSEM", "AINSEM") {
        if (factory_ == address(0) || poolManager_ == address(0) || factory_ == poolManager_) {
            revert InvalidLaunchAddress();
        }
        if (factory_ != msg.sender) revert FactoryMustDeploy();

        factory = factory_;
        poolManager = poolManager_;
        launchNumber = launchNumber_;
        _mint(msg.sender, INITIAL_SUPPLY);
    }

    function _update(address from, address to, uint256 amount) internal override {
        // Constructor minting is the only path with a zero source.
        if (from == address(0)) {
            super._update(from, to, amount);
            return;
        }

        // Check the gross debit, including on self-transfers, before doing any work.
        uint256 balance = balanceOf(from);
        if (balance < amount) revert ERC20InsufficientBalance(from, balance, amount);

        // Exactly 1%, rounded down, without an intermediate multiplication overflow.
        uint256 burnAmount = amount / 100;
        if (burnAmount != 0 && !_isExempt(from, to)) {
            super._update(from, address(0), burnAmount);
            amount -= burnAmount;
        }
        super._update(from, to, amount);
    }

    function _isExempt(address from, address to) private view returns (bool) {
        if (msg.sender == factory || msg.sender == poolManager || from == poolManager || to == poolManager) {
            return true;
        }

        // The distributor is registered after token creation; never cache an unset entry.
        address distributor = _distributor();
        return distributor != address(0) && (msg.sender == distributor || from == distributor);
    }

    /// @dev A failed or malformed registry read must not freeze ordinary holders.
    /// Only a STATICCALL is made, with bounded gas and a bounded return-data copy.
    function _distributor() private view returns (address) {
        bytes memory input = abi.encodeCall(ILaunchFactory.distributorOf, (launchNumber));
        address registry = factory;
        uint256 lookupGas = DISTRIBUTOR_LOOKUP_GAS;
        bool success;
        uint256 result;
        assembly ("memory-safe") {
            let output := mload(0x40)
            success := staticcall(lookupGas, registry, add(input, 32), mload(input), output, 32)
            success := and(success, eq(returndatasize(), 32))
            result := mload(output)
        }
        if (!success || result > type(uint160).max) return address(0);
        // The bounds check above rejects every value that this cast could truncate.
        // forge-lint: disable-next-line(unsafe-typecast)
        return address(uint160(result));
    }
}
