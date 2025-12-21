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
    enum AdminStatus {
        Initial,
        Withdrawn,
        RwaDeposited,
        ClaimAllowed
    }

    struct IDOInfo {
        IERC20 saleToken;        // RWA Token to be sold
        uint256 startTime;
        uint256 endTime;
        uint256 totalSaleAmount;   // Total RWA tokens for sale
        uint256 targetRaiseAmount; // Target USDC to raise
        uint256 totalRaised;       // Total USDC deposited by users
        AdminStatus adminStatus;   // IDO ended -> withdraw USDC -> deposit RWA -> allow claim
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
        uint256 targetRaiseAmount,
        uint256 startTime,
        uint256 endTime
    );
    event IDOTimesUpdated(
        uint256 indexed idoId, 
        uint256 startTime, 
        uint256 endTime, 
        uint256 newStartTime, 
        uint256 newEndTime
    );
    event IDOCancelled(uint256 indexed idoId);
    event AdminWithdrawn(uint256 indexed idoId, uint256 usdcAmount);
    event AdminRwaDeposited(uint256 indexed idoId, uint256 rwaAmount);
    event AdminClaimAllowed(uint256 indexed idoId);

    event Subscribed(
        uint256 indexed idoId, 
        address indexed user, 
        uint256 amount
    );
    event Claimed(
        uint256 indexed idoId, 
        address indexed user, 
        uint256 rwaAmount, 
        uint256 refundAmount
    );


    // ======================= Modifier & Constructor ======================
    modifier onlyOwner() {
        require(
            multionesAccess.hasRole(DEFAULT_ADMIN_ROLE_OVERRIDE, msg.sender), 
            "MultiOnesAccess: not owner"
        );
        _;
    }

    modifier idoIdExists(uint256 idoId) {
        require(idoId > 0 && idoId < nextIdoId, "IDO: invalid ID");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
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
        
        nextIdoId = 1;       // Start from ID 1
    }


    // ========================= Internal functions ========================
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}


    // =========================== Admin Functions =========================
    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function createIDO(
        address saleToken,
        uint256 totalSaleAmount,
        uint256 targetRaiseAmount,
        uint256 startTime,
        uint256 endTime
    ) public onlyOwner returns (uint256) {
        // Check parameters
        require(saleToken != address(0), "IDO: sale token zero address");
        require(totalSaleAmount > 0, "IDO: sale amount is zero");
        require(targetRaiseAmount > 0, "IDO: target raise is zero");
        require(startTime > block.timestamp, "IDO: start time is in the past");
        require(endTime > startTime, "IDO: invalid time range");

        // Update state variables
        uint256 idoId = nextIdoId++;
        idoInfos[idoId] = IDOInfo({
            saleToken: IERC20(saleToken),
            totalSaleAmount: totalSaleAmount,
            targetRaiseAmount: targetRaiseAmount,
            startTime: startTime,
            endTime: endTime,
            totalRaised: 0,
            adminStatus: AdminStatus.Initial
        });

        // Event
        emit IDOCreated(
            idoId, saleToken, totalSaleAmount, targetRaiseAmount, startTime, endTime
        );
        return idoId;
    }

    // Can only change `endTime` after IDO begins
    function updateIDOTimes(
        uint256 idoId, 
        uint256 newStartTime, 
        uint256 newEndTime
    ) public onlyOwner idoIdExists(idoId) {
        // Check time range
        IDOInfo storage info = idoInfos[idoId];
        uint256 startTime = info.startTime;
        uint256 endTime = info.endTime;

        if (block.timestamp < startTime) {
            require(newStartTime > block.timestamp, "IDO: invalid start time");
            require(newEndTime > newStartTime, "IDO: invalid time range");
        } else if (block.timestamp < endTime) {
            require(newStartTime == startTime, "IDO: can only change end time after started");
            require(newEndTime > block.timestamp, "IDO: invalid end time");
        } else {
            revert("IDO: already ended");
        }

        // Update state variables
        info.startTime = newStartTime;
        info.endTime = newEndTime;

        // Event
        emit IDOTimesUpdated(idoId, startTime, endTime, newStartTime, newEndTime);
    }

    // Only allowed before IDO starts
    function cancelIDO(
        uint256 idoId
    ) public onlyOwner idoIdExists(idoId) {
        // Check time range
        IDOInfo storage info = idoInfos[idoId];
        require(block.timestamp < info.startTime, "IDO: already started");

        // Update state variables
        info.startTime = type(uint256).max;
        info.endTime = type(uint256).max;

        // Event
        emit IDOCancelled(idoId);
    }

    function withdrawFunds(
        uint256 idoId
    ) public onlyOwner nonReentrant idoIdExists(idoId) {
        // Check time range & withdrawal status
        IDOInfo storage info = idoInfos[idoId];
        require(block.timestamp > info.endTime, "IDO: not ended");
        require(info.adminStatus == AdminStatus.Initial, "IDO: already withdrawn");

        // Update state, transfer token
        info.adminStatus = AdminStatus.Withdrawn;
        uint256 usdcWithdrawn;
        if (info.totalRaised <= info.targetRaiseAmount) {
            usdcWithdrawn = info.totalRaised;
        } else {
            usdcWithdrawn = info.targetRaiseAmount;
        }
        paymentToken.safeTransfer(msg.sender, usdcWithdrawn);

        // Event
        emit AdminWithdrawn(idoId, usdcWithdrawn);
    }

    function depositRWA(
        uint256 idoId
    ) public onlyOwner nonReentrant idoIdExists(idoId) {
        // Check time range & withdrawal status
        IDOInfo storage info = idoInfos[idoId];
        require(block.timestamp > info.endTime, "IDO: not ended");
        require(
            info.adminStatus == AdminStatus.Withdrawn, 
            "IDO: funds not withdrawn or RWA already deposited"
        );

        // Update state, transfer token
        uint256 rwaDeposited = 0;
        if (info.totalRaised <= info.targetRaiseAmount) {
            rwaDeposited = info.totalSaleAmount.mulDiv(info.totalRaised, info.targetRaiseAmount);
        } else {
            rwaDeposited = info.totalSaleAmount;
        }
        info.saleToken.safeTransferFrom(msg.sender, address(this), rwaDeposited);
        info.adminStatus = AdminStatus.RwaDeposited;

        // Event
        emit AdminRwaDeposited(idoId, rwaDeposited);
    }

    function allowClaim(
        uint256 idoId
    ) public onlyOwner idoIdExists(idoId) {
        IDOInfo storage info = idoInfos[idoId];
        require(info.adminStatus == AdminStatus.RwaDeposited, "IDO: RWA not deposited");
        info.adminStatus = AdminStatus.ClaimAllowed;
        emit AdminClaimAllowed(idoId);
    }


    // =========================== User Functions ==========================
    function subscribe(
        uint256 idoId, 
        uint256 amount
    ) public whenNotPaused nonReentrant idoIdExists(idoId) {
        // Check parameters
        require(amount > 0, "IDO: amount is zero");

        // Check time range
        IDOInfo storage info = idoInfos[idoId];
        require(block.timestamp >= info.startTime, "IDO: not started");
        require(block.timestamp <= info.endTime, "IDO: ended");

        // Transfer payment token
        paymentToken.safeTransferFrom(msg.sender, address(this), amount);

        // Update state variables
        userInfos[idoId][msg.sender].subscribedAmount += amount;
        info.totalRaised += amount;

        // Event
        emit Subscribed(idoId, msg.sender, amount);
    }

    function claim(uint256 idoId) public nonReentrant idoIdExists(idoId) {
        // Check time range
        IDOInfo storage info = idoInfos[idoId];
        require(block.timestamp > info.endTime, "IDO: not ended");
        require(info.adminStatus == AdminStatus.ClaimAllowed, "IDO: claim not allowed");

        // Check user info
        UserInfo storage user = userInfos[idoId][msg.sender];
        uint256 userSub = user.subscribedAmount;
        require(!user.claimed, "IDO: already claimed");
        require(userSub > 0, "IDO: no subscription");

        // Update state variables
        user.claimed = true;
        uint256 rwaAmount;
        uint256 refundAmount;

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

        // Distribute token and refund
        info.saleToken.safeTransfer(msg.sender, rwaAmount);
        if (refundAmount > 0) {
            paymentToken.safeTransfer(msg.sender, refundAmount);
        }

        // Event
        emit Claimed(idoId, msg.sender, rwaAmount, refundAmount);
    }


    // =========================== Storage Gap =============================
    uint256[50] private _gap;
}
