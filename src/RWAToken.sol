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

    /// @notice Fee denominator (10000 = 100%)
    uint256 public constant FEE_DENOMINATOR = 10000;

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

    /// @notice Buy fee rate in basis points (e.g. 100 = 1%)
    uint256 public buyFeeRate;

    /// @notice Sell fee rate in basis points (e.g. 100 = 1%)
    uint256 public sellFeeRate;

    /// @notice Address to receive fees
    address public feeCollector;


    // =============================== Events ==============================
    /// @notice Emitted when IDO mode is set
    event IdoModeSet(bool status);
    
    /// @notice Emitted when the separated teller role status is updated
    event SeparatedTellerRoleSet(bool status, address newLocalTeller);
    
    /// @notice Emitted when the maximum supply is updated
    event MaxSupplySet(uint256 newMaxSupply);

    /// @notice Emitted when fees are updated
    event FeesSet(uint256 buyFeeRate, uint256 sellFeeRate);

    /// @notice Emitted when fee collector is updated
    event FeeCollectorSet(address indexed feeCollector);

    /// @notice Emitted when a fee is collected
    event FeeCollected(address indexed user, uint256 feeAmount, bool isBuy);


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

        buyFeeRate = 0;
        sellFeeRate = 0;
        feeCollector = address(this);

        emit IdoModeSet(true);
        emit MaxSupplySet(maxSupply);
        emit FeesSet(0, 0);
        emit FeeCollectorSet(feeCollector);
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

    /// @notice Sets the buy and sell fee rates
    /// @param newBuyFeeRate Buy fee in basis points (e.g. 100 = 1%)
    /// @param newSellFeeRate Sell fee in basis points
    function setFees(uint256 newBuyFeeRate, uint256 newSellFeeRate) public onlyOwner {
        require(
            newBuyFeeRate <= 1000 && newSellFeeRate <= 1000, 
            "RWAToken: fees too high" // Max 10% safety check
        );
        buyFeeRate = newBuyFeeRate;
        sellFeeRate = newSellFeeRate;
        emit FeesSet(newBuyFeeRate, newSellFeeRate);
    }

    /// @notice Sets the fee collector address
    function setFeeCollector(address newFeeCollector) public onlyOwner {
        require(newFeeCollector != address(0), "RWAToken: zero address");
        feeCollector = newFeeCollector;
        emit FeeCollectorSet(newFeeCollector);
    }


    // =========================== User Functions ==========================
    /// @notice Simulate the amount of shares that the assets would buy
    function previewDeposit(uint256 assets) public view override returns (uint256) {
        uint256 fee = assets.mulDiv(buyFeeRate, FEE_DENOMINATOR);
        return _convertToShares(assets - fee, Math.Rounding.Floor);
    }

    /// @notice Simulate the amount of assets required to mint shares
    function previewMint(uint256 shares) public view override returns (uint256) {
        uint256 netAssets = _convertToAssets(shares, Math.Rounding.Ceil);
        // gross * (1 - fee) = net => gross = net / (1 - fee)
        return netAssets.mulDiv(
            FEE_DENOMINATOR, FEE_DENOMINATOR - buyFeeRate, Math.Rounding.Ceil
        );
    }

    /// @notice Simulate the amount of shares required to withdraw assets
    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        // gross * (1 - fee) = net => gross = net / (1 - fee)
        uint256 grossAssets = assets.mulDiv(
            FEE_DENOMINATOR, FEE_DENOMINATOR - sellFeeRate, Math.Rounding.Ceil
        );
        return _convertToShares(grossAssets, Math.Rounding.Ceil);
    }

    /// @notice Simulate the amount of assets that the shares would redeem
    function previewRedeem(uint256 shares) public view override returns (uint256) {
        uint256 grossAssets = _convertToAssets(shares, Math.Rounding.Floor);
        uint256 fee = grossAssets.mulDiv(sellFeeRate, FEE_DENOMINATOR);
        return grossAssets - fee;
    }

    /// @dev Internal deposit implementation (overrided to add fee logging & KYC check)
    /// @notice Handles both deposit() and mint() flows
    function _deposit(
        address caller, 
        address receiver, 
        uint256 assets, 
        uint256 shares
    ) internal override {
        // 1. Enforce KYC
        require(multionesAccess.isKycPassed(caller), "RWAToken: not KYC verified user");

        // 2. Perform transfer and mint
        super._deposit(caller, receiver, assets, shares);

        // 3. Log Fee and Transfer
        uint256 fee = assets.mulDiv(buyFeeRate, FEE_DENOMINATOR);
        if (fee > 0) {
            if (feeCollector != address(0)) {
                IERC20(asset()).safeTransfer(feeCollector, fee);
            }
            emit FeeCollected(caller, fee, true);
        }
    }

    /// @dev Internal withdraw implementation (overrided to add fee logging & KYC check)
    /// @notice Handles both withdraw() and redeem() flows
    function _withdraw(
        address caller, 
        address receiver, 
        address owner, 
        uint256 assets, 
        uint256 shares
    ) internal override {
        // 1. Enforce KYC
        require(multionesAccess.isKycPassed(caller), "RWAToken: not KYC verified user");

        // 2. Perform burn and transfer
        super._withdraw(caller, receiver, owner, assets, shares);

        // 3. Log Fee: Difference between Share Value (Gross) and Assets Sent (Net)
        uint256 grossAssets = _convertToAssets(shares, Math.Rounding.Floor);
        if (grossAssets > assets) {
            uint256 fee = grossAssets - assets;
            if (feeCollector != address(0)) {
                IERC20(asset()).safeTransfer(feeCollector, fee);
            }
            emit FeeCollected(caller, fee, false);
        }
    }


    // =========================== Storage Gap =============================
    uint256[46] private _gap;
}
