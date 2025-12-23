// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

import {IMultiOnesOracle} from "./interfaces/IMultiOnesOracle.sol";
import {MultiOnesBase} from "./MultiOnesAccess.sol";

/* Should have multiple instances */
contract RWAToken is 
    ERC4626Upgradeable, 
    PausableUpgradeable,
    MultiOnesBase 
{
    // ============================== Library ==============================
    using Math for uint256;
    using SafeERC20 for IERC20;


    // ============================== Storage ==============================
    uint256 public constant ORACLE_TIMEOUT = 24 hours;

    bool public idoMode;
    IMultiOnesOracle public multionesOracle;

    bool public separatedTellerRole;
    address public localTeller;

    uint256 public maxSupply;


    // =============================== Events ==============================
    event IdoModeSet(bool status);
    event SeparatedTellerRoleSet(bool status, address newLocalTeller);
    event MaxSupplySet(uint256 newMaxSupply);


    // ============================ Constructor ============================
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _asset, // Underlying asset (USDC)
        address _multionesOracle,
        address _multionesAccess,
        string memory _name,
        string memory _symbol
    ) public initializer {
        require(_multionesAccess != address(0), "RWAToken: access zero address");
        require(_multionesOracle != address(0), "RWAToken: oracle zero address");

        __ERC20_init(_name, _symbol);
        __ERC4626_init(IERC20(_asset));
        __Pausable_init();

        multionesOracle = IMultiOnesOracle(_multionesOracle);
        multionesAccess = IAccessControl(_multionesAccess);
        maxSupply = 1_000_000_000 * (10 ** decimals());

        idoMode = true;
        separatedTellerRole = false;
        emit IdoModeSet(true);
        emit MaxSupplySet(maxSupply);
    }


    // ========================= Internal functions ========================
    // To adapt for 6-decimals USDC & USDT
    function _decimalsOffset() internal pure override returns (uint8) {
        return 12;
    }

    function _isTeller(address account) internal view returns (bool) {
        if (separatedTellerRole) {
            return account == localTeller;
        } else {
            return multionesAccess.hasRole(TELLER_OPERATOR_ROLE, account);
        }
    }

    function _onlyTeller() internal override view {
        require(_isTeller(msg.sender), "RWAToken: not teller");
    }

    function _convertToShares(
        uint256 assets, 
        Math.Rounding rounding
    ) internal view override returns (uint256) {
        (uint256 price, ) = multionesOracle.getPriceSafe(address(this), ORACLE_TIMEOUT);
        // assets (6) -> shares (18)
        // shares = assets * 1e30 / price
        return assets.mulDiv(1e30, price, rounding);
    }

    function _convertToAssets(
        uint256 shares, 
        Math.Rounding rounding
    ) internal view override returns (uint256) {
        (uint256 price, ) = multionesOracle.getPriceSafe(address(this), ORACLE_TIMEOUT);
        // shares (18) -> assets (6)
        // assets = shares * price / 1e30
        return shares.mulDiv(price, 1e30, rounding);
    }

    function maxDeposit(address) public view override returns (uint256) {
        uint256 total = totalSupply();
        if (total >= maxSupply) return 0;
        
        // Calculate remaining shares capacity
        uint256 remainingShares = maxSupply - total;
        
        // Convert remaining shares to assets (USDC)
        // Round DOWN to ensure we don't exceed maxSupply
        return _convertToAssets(remainingShares, Math.Rounding.Floor);
    }

    function maxMint(address) public view override returns (uint256) {
        uint256 total = totalSupply();
        if (total >= maxSupply) return 0;
        return maxSupply - total;
    }

    /**
     * Permission Table:
     * +-------------+--------------------+----------------------+------------------------+
     * | Role / Mode |       User         |      Whitelisted     |         Teller         |
     * +-------------+--------------------+----------------------+------------------------+
     * | IDO Mode    |         -  ⬜️      |    Transfer Only 🟦   | Mint/Burn/Transfer 🟩  |
     * +-------------+--------------------+----------------------+------------------------+
     * | Normal Mode | Mint/Burn Only 🟧  | Mint/Burn/Transfer 🟩 | Mint/Burn/Transfer 🟩  |
     * +-------------+--------------------+----------------------+------------------------+
     */
    function _update(address from, address to, uint256 value) internal override whenNotPaused {
        // Check max supply on mint
        if (from == address(0)) {
            require(totalSupply() + value <= maxSupply, "RWAToken: max supply exceeded");
        }

        // 1. Teller: Always Allowed
        if (_isTeller(from) || _isTeller(to)) {
            super._update(from, to, value);
            return;
        }
        bool isMintOrBurn = (from == address(0) || to == address(0));
        bool isWhitelisted = multionesAccess.hasRole(WHITELIST_TRANSFER_ROLE, from) || 
                             multionesAccess.hasRole(WHITELIST_TRANSFER_ROLE, to);
        if (idoMode) {
            // 2. IDO Mode:
            // - User: All Forbidden
            // - Whitelist: Transfer Only (Mint/Burn Forbidden)
            require(isWhitelisted, "RWAToken: user operation not allowed");
            require(!isMintOrBurn, "RWAToken: mint/burn not allowed in IDO mode");
        } else {
            // 3. Normal Mode:
            // - Mint/Burn: Allowed for everyone (User & Whitelist)
            // - Transfer: Allowed for Whitelist Only
            require(
                isMintOrBurn || isWhitelisted,
                "RWAToken: user transfer not allowed"
            );
        }
        super._update(from, to, value);
    }


    // ====================== Admin & Teller Functions =====================
    function setIdoMode(bool status) public onlyTeller {
        idoMode = status;
        emit IdoModeSet(status);
    }

    function pause() public onlyTeller {
        _pause();
    }

    function unpause() public onlyTeller {
        _unpause();
    }

    function depositAsset(uint256 amount) public onlyTeller {
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);
    }
    
    function withdrawAsset(address to, uint256 amount) public onlyTeller {
        IERC20(asset()).safeTransfer(to, amount);
    }

    function setSeparatedTellerRole(
        address newLocalTeller,
        bool status
    ) public onlyOwner {
        separatedTellerRole = status;
        localTeller = newLocalTeller;
        emit SeparatedTellerRoleSet(status, newLocalTeller);
    }

    function setMaxSupply(uint256 newMaxSupply) public onlyOwner {
        require(newMaxSupply >= totalSupply(), "RWAToken: new max supply less than total supply");
        maxSupply = newMaxSupply;
        emit MaxSupplySet(newMaxSupply);
    }


    // =========================== User Functions ==========================
    function deposit(
        uint256 assets, 
        address receiver
    ) public override onlyKycUser returns (uint256) {
        return super.deposit(assets, receiver);
    }

    function mint(
        uint256 shares, 
        address receiver
    ) public override onlyKycUser returns (uint256) {
        return super.mint(shares, receiver);
    }

    function withdraw(
        uint256 assets, 
        address receiver, 
        address owner
    ) public override onlyKycUser returns (uint256) {
        return super.withdraw(assets, receiver, owner);
    }

    function redeem(
        uint256 shares, 
        address receiver, 
        address owner
    ) public override onlyKycUser returns (uint256) {
        return super.redeem(shares, receiver, owner);
    }


    // =========================== Storage Gap =============================
    uint256[49] private _gap;
}
