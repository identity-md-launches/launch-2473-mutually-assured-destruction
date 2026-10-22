// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Mutually Assured Destruction (MAD)
/// @notice A fixed-supply ERC-20. The whole supply of 1,000,000,000 MAD (18 decimals) is minted once,
///         in the constructor, to the deployer. There is no owner, no further minting, no pause,
///         no blocklist and no fee: transfers follow the plain ERC-20 rules forever.
/// @dev The contract name is the launch identifier (at most 32 characters); the token's long name is
///      returned by `name()`. The constructor takes no arguments and calls no other contract, so it
///      deploys on an empty chain and the launch manifest's constructorArgs list is empty.
contract MADToken is ERC20 {
    /// @notice The token's full name, as `name()` returns it.
    string public constant TOKEN_NAME = "Mutually Assured Destruction";

    /// @notice The token's ticker symbol, as `symbol()` returns it.
    string public constant TOKEN_SYMBOL = "MAD";

    /// @notice Number of decimals, as `decimals()` returns it.
    uint8 public constant TOKEN_DECIMALS = 18;

    /// @notice The whole supply in minor units: 1,000,000,000 MAD with 18 decimals.
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** uint256(TOKEN_DECIMALS);

    /// @notice Mints `TOTAL_SUPPLY` to `msg.sender` exactly once. No mint path exists afterwards.
    constructor() ERC20(TOKEN_NAME, TOKEN_SYMBOL) {
        _mint(msg.sender, TOTAL_SUPPLY);
    }
}
