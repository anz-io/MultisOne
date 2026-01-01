// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    IAccessControl, AccessControlUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";


interface IMultiOnesAccess is IAccessControl {
    function isKycPassed(address account) external view returns (bool);
}


/// @title MultiOnesBase
/// @notice Abstract base contract containing constants & modifiers for the MultiOnes protocol.
abstract contract MultiOnesBase {
    // ============================= Constants =============================
    bytes32 public constant DEFAULT_ADMIN_ROLE_OVERRIDE = 0x00; // inherit from `AccessControl`
    bytes32 public constant KYC_OPERATOR_ROLE = keccak256("KYC_OPERATOR_ROLE");
    bytes32 public constant PRICE_UPDATER_ROLE = keccak256("PRICE_UPDATER_ROLE");
    bytes32 public constant KYC_VERIFIED_USER_ROLE = keccak256("KYC_VERIFIED_USER_ROLE");
    bytes32 public constant WHITELIST_TRANSFER_ROLE = keccak256("WHITELIST_TRANSFER_ROLE");
    bytes32 public constant TELLER_OPERATOR_ROLE = keccak256("TELLER_OPERATOR_ROLE");
    uint256 public constant MAX_BATCH_SIZE_LIMIT = 100;


    // ============================== Storage ==============================
    /// @notice Reference to the MultiOnesAccess contract for role checking
    IAccessControl public multionesAccess;


    // ============================== Modifier =============================
    /// @notice Modifier to restrict access to the owner (DEFAULT_ADMIN_ROLE)
    modifier onlyOwner() {
        _onlyOwner();
        _;
    }
    
    /// @notice Modifier to restrict access to teller operators
    modifier onlyTeller() {
        _onlyTeller();
        _;
    }

    /// @notice Modifier to restrict access to KYC verified users
    modifier onlyKycUser() {
        _onlyKycUser();
        _;
    }

    /// @notice Modifier to restrict access to price updaters
    modifier onlyPriceUpdater() {
        _onlyPriceUpdater();
        _;
    }

    /// @dev Internal check for owner role. We wrapped the modifier logic to reduce code size
    function _onlyOwner() internal view {
        require(
            multionesAccess.hasRole(DEFAULT_ADMIN_ROLE_OVERRIDE, msg.sender), 
            "MultiOnesAccess: not owner"
        );
    }

    /// @dev Internal check for teller operator role
    function _onlyTeller() internal virtual view {
        require(
            multionesAccess.hasRole(TELLER_OPERATOR_ROLE, msg.sender), 
            "MultiOnesAccess: not teller operator"
        );
    }

    /// @dev Internal check for KYC verified user role
    function _onlyKycUser() internal view {
        require(
            IMultiOnesAccess(address(multionesAccess)).isKycPassed(msg.sender), 
            "MultiOnesAccess: not KYC verified user"
        );
    }

    /// @dev Internal check for price updater role
    function _onlyPriceUpdater() internal view {
        require(
            multionesAccess.hasRole(PRICE_UPDATER_ROLE, msg.sender), 
            "MultiOnesAccess: not price updater"
        );
    }
}


/// @title MultiOnesAccess
/// @notice Manages access control roles and KYC verification status for the MultiOnes protocol.
contract MultiOnesAccess is 
    AccessControlUpgradeable, 
    UUPSUpgradeable, 
    MultiOnesBase 
{
    // ============================== Storage ==============================
    /// @notice Counter for the total number of addresses that have passed KYC
    uint256 public totalKycPassedAddresses;
    
    /// @notice Switch to enable or disable KYC check
    bool public kycCheckEnabled;


    // =============================== Events ==============================
    /// @notice Emitted when the KYC check status is updated
    event KycCheckEnabled(bool status);


    // ======================= Modifier & Constructor ======================
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract with default admin roles and hierarchy
    function initialize() public initializer {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());

        _setRoleAdmin(KYC_OPERATOR_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(PRICE_UPDATER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(WHITELIST_TRANSFER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(TELLER_OPERATOR_ROLE, DEFAULT_ADMIN_ROLE);

        _setRoleAdmin(KYC_VERIFIED_USER_ROLE, KYC_OPERATOR_ROLE);

        multionesAccess = IAccessControl(address(this));
    }


    // ========================= Internal functions ========================
    /// @notice Authorizes the upgrade of the contract implementation
    function _authorizeUpgrade(address /*newImplementation*/) internal view override {
        require(
            hasRole(DEFAULT_ADMIN_ROLE_OVERRIDE, msg.sender), 
            "MultiOnesAccess: not owner"
        );
    }


    // =========================== View functions ==========================
    /// @notice Checks if an account has passed KYC verification
    /// @param account The address to check
    /// @return True if the account has the KYC_VERIFIED_USER_ROLE, false otherwise
    function isKycPassed(address account) public view returns (bool) {
        if (!kycCheckEnabled) {
            return true;
        }
        return hasRole(KYC_VERIFIED_USER_ROLE, account);
    }


    // ========================== Write functions ==========================
    /// @notice Enables or disables the KYC check
    /// @param status True to enable KYC check, false to disable
    function setKycCheckEnabled(bool status) public onlyRole(DEFAULT_ADMIN_ROLE) {
        kycCheckEnabled = status;
        emit KycCheckEnabled(status);
    }

    /// @notice Grants KYC verified status to an account
    /// @dev Same as calling `grantRole(KYC_VERIFIED_USER_ROLE, account)` by `KYC_OPERATOR_ROLE`
    /// @param account The address to be verified
    function kycPass(address account) public onlyRole(KYC_OPERATOR_ROLE) {
        if (!hasRole(KYC_VERIFIED_USER_ROLE, account)) {
            _grantRole(KYC_VERIFIED_USER_ROLE, account);
            totalKycPassedAddresses++;
        }
    }

    /// @notice Batch grants KYC verified status to multiple accounts
    /// @param accounts Array of addresses to be verified
    function kycPassBatch(address[] calldata accounts) public onlyRole(KYC_OPERATOR_ROLE) {
        require(accounts.length > 0, "MultiOnesAccess: accounts is empty");
        require(accounts.length <= MAX_BATCH_SIZE_LIMIT, "MultiOnesAccess: too many accounts");
        for (uint256 i = 0; i < accounts.length; i++) {
            if (!hasRole(KYC_VERIFIED_USER_ROLE, accounts[i])) {
                _grantRole(KYC_VERIFIED_USER_ROLE, accounts[i]);
                totalKycPassedAddresses++;
            }
        }
    }

    /// @notice Revokes KYC verified status from an account
    /// @dev Same as calling `revokeRole(KYC_VERIFIED_USER_ROLE, account)` by `KYC_OPERATOR_ROLE`
    /// @param account The address to have KYC revoked
    function kycRevoke(address account) public onlyRole(KYC_OPERATOR_ROLE) {
        if (hasRole(KYC_VERIFIED_USER_ROLE, account)) {
            _revokeRole(KYC_VERIFIED_USER_ROLE, account);
            totalKycPassedAddresses--;
        }
    }

    /// @notice Batch revokes KYC verified status from multiple accounts
    /// @param accounts Array of addresses to have KYC revoked
    function kycRevokeBatch(address[] calldata accounts) public onlyRole(KYC_OPERATOR_ROLE) {
        require(accounts.length > 0, "MultiOnesAccess: accounts is empty");
        require(accounts.length < MAX_BATCH_SIZE_LIMIT, "MultiOnesAccess: too many accounts");
        for (uint256 i = 0; i < accounts.length; i++) {
            if (hasRole(KYC_VERIFIED_USER_ROLE, accounts[i])) {
                _revokeRole(KYC_VERIFIED_USER_ROLE, accounts[i]);
                totalKycPassedAddresses--;
            }
        }
    }
    
    // =========================== Storage Gap =============================
    uint256[49] private _gap;
}
