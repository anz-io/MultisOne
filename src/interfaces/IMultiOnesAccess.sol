// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/// @title IMultiOnesAccess
/// @notice Interface for the MultiOnesAccess contract, extending IAccessControl with KYC capabilities.
interface IMultiOnesAccess is IAccessControl {
    /// @notice Checks if an account has passed KYC verification
    /// @param account The address to check
    /// @return True if the account has passed KYC, false otherwise
    function isKycPassed(address account) external view returns (bool);
}

