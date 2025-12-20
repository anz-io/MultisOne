// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {MultiOnesConstants} from "./MultiOnesAccess.sol";

contract IDO is 
    ReentrancyGuard, 
    PausableUpgradeable, 
    UUPSUpgradeable,
    MultiOnesConstants 
{
    // ============================== Library ==============================
    using SafeERC20 for IERC20;
    using Math for uint256;
    

    // ============================== Structs ==============================
    struct IDOInfo {
        IERC20 saleToken;        // RWA Token to be sold
        uint256 startTime;
        uint256 endTime;
        uint256 totalSaleAmount;   // Total RWA tokens for sale
        uint256 targetRaiseAmount; // Target USDC to raise (Hard Cap)
        uint256 totalRaised;       // Total USDC deposited by users
        bool withdrawn;            // Whether admin has withdrawn funds
    }

    struct UserInfo {
        uint256 subscribedAmount;  // Amount of USDC deposited
        bool claimed;              // Whether user has claimed
    }


    // ============================== Storage ==============================
    IERC20 public paymentToken; // USDC (Universal for all IDOs)
    IAccessControl public multionesAccess;

    uint256 public nextIdoId;
    mapping(uint256 => IDOInfo) public idoInfos;
    // idoId => user => UserInfo
    mapping(uint256 => mapping(address => UserInfo)) public userInfos;

    // =============================== Events ==============================
    event IDOCreated(
        uint256 indexed idoId, 
        address indexed saleToken, 
        uint256 totalSaleAmount, 
        uint256 targetRaiseAmount
    );
    event IDOTimesUpdated(uint256 indexed idoId, uint256 startTime, uint256 endTime);
    event Subscribed(uint256 indexed idoId, address indexed user, uint256 amount);
    event Claimed(uint256 indexed idoId, address indexed user, uint256 rwaAmount, uint256 refundAmount);
    event AdminWithdrawn(uint256 indexed idoId, uint256 usdcAmount, uint256 rwaAmount);

    // ======================= Modifier & Constructor ======================
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    modifier onlyOwner() {
        require(
            multionesAccess.hasRole(DEFAULT_ADMIN_ROLE_OVERRIDE, msg.sender), 
            "MultiOnesAccess: not owner"
        );
        _;
    }

    function initialize(
        address _paymentToken,
        address _multionesAccess
    ) public initializer {
        require(_paymentToken != address(0), "IDO: payment token zero address");
        require(_multionesAccess != address(0), "IDO: access zero address");

        __Pausable_init();
        
        paymentToken = IERC20(_paymentToken);
        multionesAccess = IAccessControl(_multionesAccess);
        
        nextIdoId = 1; // Start from ID 1
    }


    // ========================= Internal functions ========================
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}


    // =========================== Admin Functions =========================
    function createIDO(
        address _saleToken,
        uint256 _totalSaleAmount,
        uint256 _targetRaiseAmount
    ) external onlyOwner returns (uint256) {
        require(_saleToken != address(0), "IDO: sale token zero address");
        require(_totalSaleAmount > 0, "IDO: sale amount is zero");
        require(_targetRaiseAmount > 0, "IDO: target raise is zero");

        uint256 idoId = nextIdoId++;
        
        IDOInfo storage info = idoInfos[idoId];
        info.saleToken = IERC20(_saleToken);
        info.totalSaleAmount = _totalSaleAmount;
        info.targetRaiseAmount = _targetRaiseAmount;
        // Times are 0 by default, set later via setIDOTimes

        emit IDOCreated(idoId, _saleToken, _totalSaleAmount, _targetRaiseAmount);
        return idoId;
    }

    function setIDOTimes(uint256 idoId, uint256 _startTime, uint256 _endTime) external onlyOwner {
        require(idoId > 0 && idoId < nextIdoId, "IDO: invalid ID");
        require(_endTime > _startTime, "IDO: invalid time range");
        
        IDOInfo storage info = idoInfos[idoId];
        info.startTime = _startTime;
        info.endTime = _endTime;

        emit IDOTimesUpdated(idoId, _startTime, _endTime);
    }

    function withdrawFunds(uint256 idoId) external onlyOwner nonReentrant {
        require(idoId > 0 && idoId < nextIdoId, "IDO: invalid ID");
        IDOInfo storage info = idoInfos[idoId];

        require(block.timestamp > info.endTime, "IDO: not ended");
        require(info.endTime != 0, "IDO: time not set");
        require(!info.withdrawn, "IDO: already withdrawn");

        info.withdrawn = true;

        uint256 usdcToWithdraw;
        uint256 rwaToWithdraw;
        uint256 currentRwaBalance = info.saleToken.balanceOf(address(this));

        if (info.totalRaised <= info.targetRaiseAmount) {
            // Under-subscribed or Exact: Admin gets all raised USDC
            usdcToWithdraw = info.totalRaised;
            
            // Admin gets unsold RWA
            uint256 soldRwa = info.totalRaised.mulDiv(info.totalSaleAmount, info.targetRaiseAmount);
            if (info.totalSaleAmount > soldRwa) {
                rwaToWithdraw = info.totalSaleAmount - soldRwa;
            }
        } else {
            // Over-subscribed: Admin gets target raise amount
            usdcToWithdraw = info.targetRaiseAmount;
            rwaToWithdraw = 0;
        }

        // Safety check for RWA balance
        if (rwaToWithdraw > currentRwaBalance) {
            rwaToWithdraw = currentRwaBalance;
        }

        if (usdcToWithdraw > 0) {
            paymentToken.safeTransfer(msg.sender, usdcToWithdraw);
        }
        
        if (rwaToWithdraw > 0) {
            info.saleToken.safeTransfer(msg.sender, rwaToWithdraw);
        }

        emit AdminWithdrawn(idoId, usdcToWithdraw, rwaToWithdraw);
    }

    function setPause(bool _paused) external onlyOwner {
        if (_paused) {
            _pause();
        } else {
            _unpause();
        }
    }


    // =========================== User Functions ==========================

    function subscribe(uint256 idoId, uint256 amount) external whenNotPaused nonReentrant {
        require(idoId > 0 && idoId < nextIdoId, "IDO: invalid ID");
        require(amount > 0, "IDO: amount is zero");

        IDOInfo storage info = idoInfos[idoId];
        require(info.startTime > 0 && info.endTime > 0, "IDO: time not set");
        require(block.timestamp >= info.startTime, "IDO: not started");
        require(block.timestamp <= info.endTime, "IDO: ended");

        paymentToken.safeTransferFrom(msg.sender, address(this), amount);
        
        UserInfo storage user = userInfos[idoId][msg.sender];
        user.subscribedAmount += amount;
        info.totalRaised += amount;

        emit Subscribed(idoId, msg.sender, amount);
    }

    function claim(uint256 idoId) external nonReentrant {
        require(idoId > 0 && idoId < nextIdoId, "IDO: invalid ID");
        
        IDOInfo storage info = idoInfos[idoId];
        require(block.timestamp > info.endTime, "IDO: not ended");

        UserInfo storage user = userInfos[idoId][msg.sender];
        require(!user.claimed, "IDO: already claimed");
        require(user.subscribedAmount > 0, "IDO: no subscription");

        user.claimed = true;
        
        uint256 rwaAmount;
        uint256 refundAmount;
        uint256 userSub = user.subscribedAmount;

        if (info.totalRaised <= info.targetRaiseAmount) {
            // Under-subscribed or Exact
            rwaAmount = userSub.mulDiv(info.totalSaleAmount, info.targetRaiseAmount);
            refundAmount = 0;
        } else {
            // Over-subscribed: ProRate
            rwaAmount = userSub.mulDiv(info.totalSaleAmount, info.totalRaised);
            uint256 cost = userSub.mulDiv(info.targetRaiseAmount, info.totalRaised);
            
            if (cost > userSub) cost = userSub;
            refundAmount = userSub - cost;
        }

        if (rwaAmount > 0) {
            info.saleToken.safeTransfer(msg.sender, rwaAmount);
        }
        
        if (refundAmount > 0) {
            paymentToken.safeTransfer(msg.sender, refundAmount);
        }

        emit Claimed(idoId, msg.sender, rwaAmount, refundAmount);
    }
    

    // =========================== Storage Gap =============================
    uint256[50] private _gap;
}
