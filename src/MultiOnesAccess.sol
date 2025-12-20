// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";


abstract contract MultiOnesConstants {
    // ============================= Constants =============================
    bytes32 public constant DEFAULT_ADMIN_ROLE_OVERRIDE = 0x00;
    bytes32 public constant KYC_OPERATOR_ROLE = keccak256("KYC_OPERATOR_ROLE");
    bytes32 public constant PRICE_UPDATER_ROLE = keccak256("PRICE_UPDATER_ROLE");
    bytes32 public constant KYC_VERIFIED_USER_ROLE = keccak256("KYC_VERIFIED_USER_ROLE");
    bytes32 public constant WHITELIST_TRANSFER_ROLE = keccak256("WHITELIST_TRANSFER_ROLE");
    bytes32 public constant TELLER_OPERATOR_ROLE = keccak256("TELLER_OPERATOR_ROLE");
    uint256 public constant MAX_BATCH_SIZE_LIMIT = 100;
}


contract MultiOnesAccess is 
    AccessControlUpgradeable, 
    UUPSUpgradeable, 
    MultiOnesConstants 
{

    // ============================= Parameters ============================
    uint256 public totalKycPassedAddresses;
    

    // ======================= Modifier & Constructor ======================
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());

        _setRoleAdmin(KYC_OPERATOR_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(PRICE_UPDATER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(WHITELIST_TRANSFER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(TELLER_OPERATOR_ROLE, DEFAULT_ADMIN_ROLE);

        _setRoleAdmin(KYC_VERIFIED_USER_ROLE, KYC_OPERATOR_ROLE);
    }


    // ========================= Internal functions ========================
    function _authorizeUpgrade(address) internal view override {
        require(
            hasRole(DEFAULT_ADMIN_ROLE_OVERRIDE, msg.sender), 
            "MultiOnesAccess: not owner"
        );
    }


    // =========================== View functions ==========================
    function isKycPassed(address account) public view returns (bool) {
        return hasRole(KYC_VERIFIED_USER_ROLE, account);
    }


    // ========================== Write functions ==========================
    // Same as calling `grantRole(KYC_VERIFIED_USER_ROLE, account)` by `KYC_OPERATOR_ROLE`
    function kycPass(address account) public onlyRole(KYC_OPERATOR_ROLE) {
        if (!hasRole(KYC_VERIFIED_USER_ROLE, account)) {
            _grantRole(KYC_VERIFIED_USER_ROLE, account);
            totalKycPassedAddresses++;
        }
    }

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

    // Same as calling `revokeRole(KYC_VERIFIED_USER_ROLE, account)` by `KYC_OPERATOR_ROLE`
    function kycRevoke(address account) public onlyRole(KYC_OPERATOR_ROLE) {
        if (hasRole(KYC_VERIFIED_USER_ROLE, account)) {
            _revokeRole(KYC_VERIFIED_USER_ROLE, account);
            totalKycPassedAddresses--;
        }
    }

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
    uint256[50] private _gap;
}
