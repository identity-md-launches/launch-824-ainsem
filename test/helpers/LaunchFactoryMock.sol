// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AINSEM} from "../../src/AINSEM.sol";

/// @dev Local launch fixture; not a production factory or application contract.
contract LaunchFactoryMock {
    address private immutable controller = msg.sender;
    mapping(uint64 => address) public distributorOf;

    modifier onlyController() {
        require(msg.sender == controller, "test controller only");
        _;
    }

    function deploy(address manager, uint64 launchNumber) external onlyController returns (AINSEM) {
        return new AINSEM{salt: bytes32(uint256(launchNumber))}(address(this), manager, launchNumber);
    }

    function register(uint64 launchNumber, address distributor) external onlyController {
        distributorOf[launchNumber] = distributor;
    }

    function move(AINSEM token, address to, uint256 amount) external onlyController {
        require(token.transfer(to, amount));
    }
}
