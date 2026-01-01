// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

import {MultiOnesBase} from "./MultiOnesAccess.sol";
import {IMultiOnesAccess} from "./interfaces/IMultiOnesAccess.sol";
import {IMultiOnesOracle} from "./interfaces/IMultiOnesOracle.sol";

/// @title RWAToken
/// @notice ERC4626-compliant RWA token with access control and IDO capabilities.
contract RWAToken is 
    ERC4626Upgradeable, 
    PausableUpgradeable,
    MultiOnesBase 
{
    // ============================== Library ==============================
    using Math for uint256;
    using SafeERC20 for IERC20;


    // ============================== Storage ==============================
    /// @notice Time duration before oracle price is considered stale
    uint256 public constant ORACLE_TIMEOUT = 24 hours;

    /// @notice Whether the token is in IDO mode
    bool public idoMode;
    
    /// @notice Reference to the oracle contract
    IMultiOnesOracle public multionesOracle;

    /// @notice Whether a separate local teller role is used
    bool public separatedTellerRole;
    
    /// @notice Address of the local teller if separated
    address public localTeller;

    /// @notice Maximum supply of the RWA token
    uint256 public maxSupply;


    // =============================== Events ==============================
    /// @notice Emitted when IDO mode is set
    event IdoModeSet(bool status);
    
    /// @notice Emitted when the separated teller role status is updated
    event SeparatedTellerRoleSet(bool status, address newLocalTeller);
    
    /// @notice Emitted when the maximum supply is updated
    event MaxSupplySet(uint256 newMaxSupply);


    // ============================ Constructor ============================
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the RWA Token
    /// @dev Should be called through the `RWATokenFactory` contract
    /// @param _asset The underlying asset address (e.g., USDC)
    /// @param _multionesOracle The oracle contract address
    /// @param _multionesAccess The access control contract address
    /// @param _name The token name
    /// @param _symbol The token symbol
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
        multionesAccess = IMultiOnesAccess(_multionesAccess);
        maxSupply = 1_000_000_000 * (10 ** decimals());

        idoMode = true;
        separatedTellerRole = false;
        emit IdoModeSet(true);
        emit MaxSupplySet(maxSupply);
    }


    // ========================= Internal functions ========================
    /// @notice Returns the number of decimals offset between the token and the asset
    /// @dev To adapt for 6-decimals USDC & USDT (12 + 6 = 18, expected 18 decimals)
    function _decimalsOffset() internal pure override returns (uint8) {
        return 12;
    }

    /// @notice Checks if an account has the teller role
    /// @dev Also adapted for separated teller role
    function _isTeller(address account) internal view returns (bool) {
        if (separatedTellerRole) {
            return account == localTeller;
        } else {
            return multionesAccess.hasRole(TELLER_OPERATOR_ROLE, account);
        }
    }

    /// @notice Internal check to ensure the caller is a teller
    function _onlyTeller() internal override view {
        require(_isTeller(msg.sender), "RWAToken: not teller");
    }

    /// @notice Converts assets to shares using oracle price (overrided logic from ERC4626)
    function _convertToShares(
        uint256 assets, 
        Math.Rounding rounding
    ) internal view override returns (uint256) {
        (uint256 price, ) = multionesOracle.getPriceSafe(address(this), ORACLE_TIMEOUT);
        // assets (6) -> shares (18)
        // shares = assets * 1e30 / price
        return assets.mulDiv(1e30, price, rounding);
    }

    /// @notice Converts shares to assets using oracle price (overrided logic from ERC4626)
    function _convertToAssets(
        uint256 shares, 
        Math.Rounding rounding
    ) internal view override returns (uint256) {
        (uint256 price, ) = multionesOracle.getPriceSafe(address(this), ORACLE_TIMEOUT);
        // shares (18) -> assets (6)
        // assets = shares * price / 1e30
        return shares.mulDiv(price, 1e30, rounding);
    }

    /// @notice Returns the maximum amount of assets that can be deposited (overrided)
    function maxDeposit(address) public view override returns (uint256) {
        uint256 total = totalSupply();
        if (total >= maxSupply) return 0;
        
        // Calculate remaining shares capacity
        uint256 remainingShares = maxSupply - total;
        
        // Convert remaining shares to assets (USDC)
        // Round DOWN to ensure we don't exceed maxSupply
        return _convertToAssets(remainingShares, Math.Rounding.Floor);
    }

    /// @notice Returns the maximum amount of shares that can be minted (overrided)
    function maxMint(address) public view override returns (uint256) {
        uint256 total = totalSupply();
        if (total >= maxSupply) return 0;
        return maxSupply - total;
    }

    /**
     * @notice Permission Table:
     * +-------------+--------------------+----------------------+------------------------+
     * | Role / Mode |       User         |      Whitelisted     |         Teller         |
     * +-------------+--------------------+----------------------+------------------------+
     * | IDO Mode    |         -  ⬜️      |    Transfer Only 🟦   | Mint/Burn/Transfer 🟩  |
     * +-------------+--------------------+----------------------+------------------------+
     * | Normal Mode | Mint/Burn Only 🟧  | Mint/Burn/Transfer 🟩 | Mint/Burn/Transfer 🟩  |
     * +-------------+--------------------+----------------------+------------------------+
     */
    /// @dev Hooks into the update function to enforce permissions
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
    /// @notice Sets the IDO mode status
    function setIdoMode(bool status) public onlyTeller {
        idoMode = status;
        emit IdoModeSet(status);
    }

    /// @notice Pauses the contract
    function pause() public onlyTeller {
        _pause();
    }

    /// @notice Unpauses the contract
    function unpause() public onlyTeller {
        _unpause();
    }

    /// @notice Deposits underlying assets into the contract
    function depositAsset(uint256 amount) public onlyTeller {
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);
    }
    
    /// @notice Withdraws underlying assets from the contract
    function withdrawAsset(address to, uint256 amount) public onlyTeller {
        IERC20(asset()).safeTransfer(to, amount);
    }

    /// @notice Sets whether to use a separate local teller role
    /// @param newLocalTeller The address of the new local teller
    /// @param status True to enable separated teller role, false otherwise
    function setSeparatedTellerRole(
        address newLocalTeller,
        bool status
    ) public onlyOwner {
        separatedTellerRole = status;
        localTeller = newLocalTeller;
        emit SeparatedTellerRoleSet(status, newLocalTeller);
    }

    /// @notice Sets the maximum supply of the token
    function setMaxSupply(uint256 newMaxSupply) public onlyOwner {
        require(
            newMaxSupply >= totalSupply(), 
            "RWAToken: new max supply less than total supply"
        );
        maxSupply = newMaxSupply;
        emit MaxSupplySet(newMaxSupply);
    }


    // =========================== User Functions ==========================
    /// @notice Deposits assets to mint shares, restricted to KYC users (overrided)
    function deposit(
        uint256 assets, 
        address receiver
    ) public override onlyKycUser returns (uint256) {
        return super.deposit(assets, receiver);
    }

    /// @notice Mints shares by depositing assets, restricted to KYC users (overrided)
    function mint(
        uint256 shares, 
        address receiver
    ) public override onlyKycUser returns (uint256) {
        return super.mint(shares, receiver);
    }

    /// @notice Withdraws assets by burning shares, restricted to KYC users (overrided)
    function withdraw(
        uint256 assets, 
        address receiver, 
        address owner
    ) public override onlyKycUser returns (uint256) {
        return super.withdraw(assets, receiver, owner);
    }

    /// @notice Redeems shares for assets, restricted to KYC users (overrided)
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
