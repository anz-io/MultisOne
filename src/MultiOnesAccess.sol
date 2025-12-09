// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";


abstract contract MultiOnesConstants {
    bytes32 public constant DEFAULT_ADMIN_ROLE_OVERRIDE = 0x00;
    bytes32 public constant KYC_OPERATOR_ROLE = keccak256("KYC_OPERATOR_ROLE");
    bytes32 public constant PRICE_UPDATER_ROLE = keccak256("PRICE_UPDATER_ROLE");
    bytes32 public constant KYC_VERIFIED_USER_ROLE = keccak256("KYC_VERIFIED_USER_ROLE");
    bytes32 public constant WHITELIST_TRANSFER_ROLE = keccak256("WHITELIST_TRANSFER_ROLE");
}


contract MultiOnesAccess is MultiOnesConstants, UUPSUpgradeable, AccessControlUpgradeable {

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

        _setRoleAdmin(KYC_VERIFIED_USER_ROLE, KYC_OPERATOR_ROLE);
    }

    function _authorizeUpgrade(address) internal view override {
        require(
            hasRole(DEFAULT_ADMIN_ROLE_OVERRIDE, msg.sender), 
            "MultiOnesAccess: not owner"
        );
    }

    // Same as calling `grantRole(KYC_VERIFIED_USER_ROLE, account)` by `KYC_OPERATOR_ROLE`
    function kycPass(address account) public onlyRole(KYC_OPERATOR_ROLE) {
        _grantRole(KYC_VERIFIED_USER_ROLE, account);
    }

    function kycPassBatch(address[] calldata accounts) public onlyRole(KYC_OPERATOR_ROLE) {
        require(accounts.length > 0, "MultiOnesAccess: accounts is empty");
        require(accounts.length <= 100, "MultiOnesAccess: accounts is too many");
        for (uint256 i = 0; i < accounts.length; i++) {
            _grantRole(KYC_VERIFIED_USER_ROLE, accounts[i]);
        }
    }

    // Same as calling `revokeRole(KYC_VERIFIED_USER_ROLE, account)` by `KYC_OPERATOR_ROLE`
    function kycRevoke(address account) public onlyRole(KYC_OPERATOR_ROLE) {
        _revokeRole(KYC_VERIFIED_USER_ROLE, account);
    }

    function kycRevokeBatch(address[] calldata accounts) public onlyRole(KYC_OPERATOR_ROLE) {
        require(accounts.length > 0, "MultiOnesAccess: accounts is empty");
        require(accounts.length <= 100, "MultiOnesAccess: accounts is too many");
        for (uint256 i = 0; i < accounts.length; i++) {
            _revokeRole(KYC_VERIFIED_USER_ROLE, accounts[i]);
        }
    }
    
}
