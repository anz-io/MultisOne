// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IMultiOnesOracle} from "./interfaces/IMultiOnesOracle.sol";
import {MultiOnesConstants} from "./MultiOnesAccess.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

contract RWAToken is 
    Initializable, 
    ERC4626Upgradeable, 
    PausableUpgradeable, 
    UUPSUpgradeable, 
    MultiOnesConstants 
{
    using Math for uint256;

    // ============================== Storage ==============================
    IMultiOnesOracle public multionesOracle;
    IAccessControl public multionesAccess;
    uint256 public constant ORACLE_TIMEOUT = 24 hours;


    // ======================= Modifier & Constructor ======================
    modifier onlyOwner() {
        require(
            multionesAccess.hasRole(DEFAULT_ADMIN_ROLE_OVERRIDE, msg.sender), 
            "MultiOnesAccess: not owner"
        );
        _;
    }

    modifier onlyTeller() {
        require(
            multionesAccess.hasRole(TELLER_OPERATOR_ROLE, msg.sender), 
            "MultiOnesAccess: not teller operator"
        );
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _asset, // Underlying asset (USDC)
        address _oracle,
        address _multionesAccess,
        string memory _name,
        string memory _symbol
    ) public initializer {
        require(_multionesAccess != address(0), "RWAToken: access zero address");
        require(_oracle != address(0), "RWAToken: oracle zero address");

        __ERC20_init(_name, _symbol);
        __ERC4626_init(IERC20(_asset));
        __Pausable_init();
        __UUPSUpgradeable_init();

        multionesOracle = IMultiOnesOracle(_oracle);
        multionesAccess = IAccessControl(_multionesAccess);
    }


    // ========================= Internal functions ========================
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view override returns (uint256) {
        (uint256 price, ) = multionesOracle.getPriceSafe(address(this), ORACLE_TIMEOUT);
        // assets (6) -> shares (18)
        // shares = assets * 1e30 / price
        return assets.mulDiv(1e30, price, rounding);
    }

    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view override returns (uint256) {
        (uint256 price, ) = multionesOracle.getPriceSafe(address(this), ORACLE_TIMEOUT);
        // shares (18) -> assets (6)
        // assets = shares * price / 1e30
        return shares.mulDiv(price, 1e30, rounding);
    }

    function _update(address from, address to, uint256 value) internal override whenNotPaused {
        // Allow Mint (from 0) and Burn (to 0)
        if (
            from == address(0) || to == address(0) ||
            multionesAccess.hasRole(WHITELIST_TRANSFER_ROLE, from) ||
            multionesAccess.hasRole(WHITELIST_TRANSFER_ROLE, to)
        ) {
            super._update(from, to, value);
            return;
        } else {
            revert("RWAToken: not whitelisted");
        }
    }


    // =========================== View functions ==========================


    // =========================== Teller Functions ========================
    function pause() external onlyTeller {
        _pause();
    }

    function unpause() external onlyTeller {
        _unpause();
    }

    function tellerMint(address to, uint256 amount) external onlyTeller {
        _mint(to, amount);
    }

    function tellerBurn(address from, uint256 amount) external onlyTeller {
        _burn(from, amount);
    }

    function depositAsset(uint256 amount) external onlyTeller {
        IERC20(asset()).transferFrom(msg.sender, address(this), amount);
    }
    
    function withdrawAsset(address to, uint256 amount) external onlyTeller {
        IERC20(asset()).transfer(to, amount);
    }


    // =========================== Storage Gap =============================
    uint256[50] private __gap;
}
