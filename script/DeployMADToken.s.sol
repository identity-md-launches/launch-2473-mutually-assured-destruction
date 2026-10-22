// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {MADToken} from "../src/MADToken.sol";

/// @notice Reviewable deployment helper. The IMD launch deploys the token itself through its factory,
///         so this script is for local or stand-alone deployments only. The token takes no
///         constructor arguments: whoever deploys it receives the whole supply.
contract DeployMADToken is Script {
    /// @notice Deploys the token. Called directly by tests; `run()` wraps it in a broadcast.
    function deploy() public returns (MADToken token) {
        token = new MADToken();
    }

    function run() external returns (MADToken token) {
        vm.startBroadcast();
        token = deploy();
        vm.stopBroadcast();
    }
}
