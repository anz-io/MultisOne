// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {MultiOnesConstants} from "./MultiOnesAccess.sol";

contract IDO is 
    ReentrancyGuard, 
    UUPSUpgradeable,
    Initializable,
    MultiOnesConstants 
{
    // ============================== Library ==============================
    using SafeERC20 for IERC20;
    using Math for uint256;
    

    // ============================== Structs ==============================
    enum AdminStatus {
        Active,
        Withdrawn,
        Settled,
        ClaimAllowed,
        Cancelled
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
    mapping(uint256 => IDOInfo) public idoConfig;

    // idoId => user => UserInfo
    mapping(uint256 => mapping(address => UserInfo)) public participations;


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
        require(_paymentToken != address(0), "IDO: zero address");
        require(_multionesAccess != address(0), "IDO: zero address");

        paymentToken = IERC20(_paymentToken);
        multionesAccess = IAccessControl(_multionesAccess);
        
        nextIdoId = 1;       // Start from ID 1
    }


    // ========================= Internal functions ========================
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}


    // =========================== Admin Functions =========================
    function createIDO(
        address saleToken,
        uint256 totalSaleAmount,
        uint256 targetRaiseAmount,
        uint256 startTime,
        uint256 endTime
    ) public onlyOwner returns (uint256) {
        // Check parameters
        require(saleToken != address(0), "IDO: zero address");
        require(totalSaleAmount > 0, "IDO: zero sale amount");
        require(targetRaiseAmount > 0, "IDO: zero target raise amount");
        require(startTime > block.timestamp, "IDO: start in past");
        require(endTime > startTime, "IDO: invalid times");

        // Update state variables
        uint256 idoId = nextIdoId++;
        idoConfig[idoId] = IDOInfo({
            saleToken: IERC20(saleToken),
            totalSaleAmount: totalSaleAmount,
            targetRaiseAmount: targetRaiseAmount,
            startTime: startTime,
            endTime: endTime,
            totalRaised: 0,
            adminStatus: AdminStatus.Active
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
        IDOInfo storage info = idoConfig[idoId];
        uint256 startTime = info.startTime;
        uint256 endTime = info.endTime;

        if (block.timestamp < startTime) {
            require(newStartTime > block.timestamp, "IDO: invalid start time");
            require(newEndTime > newStartTime, "IDO: invalid times");
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
        IDOInfo storage info = idoConfig[idoId];
        require(block.timestamp < info.startTime, "IDO: already started");
        require(info.adminStatus == AdminStatus.Active, "IDO: wrong status");

        // Update state variables
        info.adminStatus = AdminStatus.Cancelled;

        // Event
        emit IDOCancelled(idoId);
    }

    function withdrawFunds(
        uint256 idoId
    ) public onlyOwner nonReentrant idoIdExists(idoId) {
        // Check time range & withdrawal status
        IDOInfo storage info = idoConfig[idoId];
        require(block.timestamp > info.endTime, "IDO: not ended");
        require(info.adminStatus == AdminStatus.Active, "IDO: already withdrawn");

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
        IDOInfo storage info = idoConfig[idoId];
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
        info.adminStatus = AdminStatus.Settled;

        // Event
        emit AdminRwaDeposited(idoId, rwaDeposited);
    }

    function allowClaim(
        uint256 idoId
    ) public onlyOwner idoIdExists(idoId) {
        IDOInfo storage info = idoConfig[idoId];
        require(info.adminStatus == AdminStatus.Settled, "IDO: RWA not deposited");
        info.adminStatus = AdminStatus.ClaimAllowed;
        emit AdminClaimAllowed(idoId);
    }


    // =========================== User Functions ==========================
    function subscribe(
        uint256 idoId, 
        uint256 amount
    ) public nonReentrant idoIdExists(idoId) {
        // Check parameters
        require(amount > 0, "IDO: zero amount");

        // Check time range
        IDOInfo storage info = idoConfig[idoId];
        require(info.adminStatus != AdminStatus.Cancelled, "IDO: cancelled");
        require(block.timestamp >= info.startTime, "IDO: not started");
        require(block.timestamp <= info.endTime, "IDO: ended");

        // Transfer payment token
        paymentToken.safeTransferFrom(msg.sender, address(this), amount);

        // Update state variables
        participations[idoId][msg.sender].subscribedAmount += amount;
        info.totalRaised += amount;

        // Event
        emit Subscribed(idoId, msg.sender, amount);
    }

    function claim(uint256 idoId) public nonReentrant idoIdExists(idoId) {
        IDOInfo storage info = idoConfig[idoId];
        UserInfo storage user = participations[idoId][msg.sender];
        uint256 subscribedAmount = user.subscribedAmount;

        require(!user.claimed, "IDO: already claimed");
        require(subscribedAmount > 0, "IDO: no subscription");

        // Check time range and status
        require(block.timestamp > info.endTime, "IDO: not ended");
        require(info.adminStatus == AdminStatus.ClaimAllowed, "IDO: claim not allowed");

        // Update state variables
        user.claimed = true;
        uint256 rwaAmount;
        uint256 refundAmount;

        if (info.totalRaised <= info.targetRaiseAmount) {
            // Under-subscribed or Exact
            rwaAmount = subscribedAmount.mulDiv(info.totalSaleAmount, info.targetRaiseAmount);
            refundAmount = 0;
        } else {
            // Over-subscribed: ProRate
            rwaAmount = subscribedAmount.mulDiv(info.totalSaleAmount, info.totalRaised);
            uint256 cost = subscribedAmount.mulDiv(info.targetRaiseAmount, info.totalRaised);
            
            if (cost > subscribedAmount) cost = subscribedAmount;
            refundAmount = subscribedAmount - cost;
        }

        // Distribute token and refund
        info.saleToken.safeTransfer(msg.sender, rwaAmount);
        if (refundAmount > 0) {
            paymentToken.safeTransfer(msg.sender, refundAmount);
        }

        // Event
        emit Claimed(idoId, msg.sender, rwaAmount, refundAmount);
    }

    function refundWhenCancelled(uint256 idoId) public nonReentrant idoIdExists(idoId) {
        // Check conditions
        IDOInfo storage info = idoConfig[idoId];
        UserInfo storage user = participations[idoId][msg.sender];
        uint256 subscribedAmount = user.subscribedAmount;

        require(info.adminStatus == AdminStatus.Cancelled, "IDO: not cancelled");
        require(!user.claimed, "IDO: already claimed");
        require(subscribedAmount > 0, "IDO: no subscription");

        // Update state
        user.claimed = true;
        
        // Refund full amount
        paymentToken.safeTransfer(msg.sender, subscribedAmount);
        
        emit Claimed(idoId, msg.sender, 0, subscribedAmount);
    }


    // =========================== Storage Gap =============================
    uint256[50] private _gap;
}
