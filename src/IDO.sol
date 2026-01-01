// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {MultiOnesBase} from "./MultiOnesAccess.sol";
import {IMultiOnesAccess} from "./interfaces/IMultiOnesAccess.sol";

/// @title IDO
/// @notice Manages the Initial Decentralized Offering (IDO) process for RWA tokens.
/// @dev Handles subscription, RWA token distribution, and refund logic.
contract IDO is 
    UUPSUpgradeable,
    Initializable,
    MultiOnesBase 
{
    // ============================== Library ==============================
    using SafeERC20 for IERC20;
    using Math for uint256;
    

    // ============================== Structs ==============================
    /// @notice Status of the IDO Admin process
    enum AdminStatus {
        Active,
        Withdrawn,
        Settled,
        ClaimAllowed,
        Cancelled
    }

    /// @notice Struct containing detailed information about an IDO
    struct IdoInfo {
        IERC20 saleToken;        // RWA Token to be sold
        uint64 startTime;
        uint64 endTime;
        uint256 totalSaleAmount;   // Total RWA tokens for sale
        uint256 targetRaiseAmount; // Target USDC to raise
        uint256 totalRaised;       // Total USDC deposited by users
        AdminStatus adminStatus;   // IDO ended -> withdraw USDC -> deposit RWA -> allow claim
    }

    /// @notice Struct containing user participation details
    struct UserInfo {
        uint256 subscribedAmount;  // Amount of USDC deposited
        bool claimed;              // Whether user has claimed
    }


    // ============================== Storage ==============================
    /// @notice The payment token accepted for subscriptions (e.g., USDC)
    IERC20 public paymentToken;

    /// @notice Counter for the next IDO ID
    uint256 public nextIdoId;
    
    /// @notice Mapping for IDO ID => its information
    mapping(uint256 => IdoInfo) public idoInfos;

    /// @notice Mapping for IDO ID => user address => user info
    // idoId => user => UserInfo
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;


    // =============================== Events ==============================
    /// @notice Emitted when a new IDO is created
    event IDOCreated(
        uint256 indexed idoId, 
        address indexed saleToken, 
        uint256 targetRaiseAmount,
        uint64 startTime,
        uint64 endTime
    );
    
    /// @notice Emitted when IDO times are updated
    event IDOTimesUpdated(
        uint256 indexed idoId, 
        uint64 startTime, 
        uint64 endTime, 
        uint64 newStartTime, 
        uint64 newEndTime
    );
    
    /// @notice Emitted when an IDO is cancelled
    event IDOCancelled(uint256 indexed idoId);
    
    /// @notice Emitted when funds are withdrawn by the admin
    event AdminWithdrawn(uint256 indexed idoId, uint256 usdcAmount);
    
    /// @notice Emitted when RWA tokens are deposited by the admin
    event AdminRwaDeposited(uint256 indexed idoId, uint256 rwaAmount);
    
    /// @notice Emitted when claiming is allowed by the admin
    event AdminClaimAllowed(uint256 indexed idoId);

    /// @notice Emitted when a user subscribes to an IDO
    event Subscribed(
        uint256 indexed idoId, 
        address indexed user, 
        uint256 amount
    );
    
    /// @notice Emitted when a user claims their RWA tokens and/or refund
    event Claimed(
        uint256 indexed idoId, 
        address indexed user, 
        uint256 rwaAmount, 
        uint256 refundAmount
    );
    
    /// @notice Emitted when a user gets a refund from a cancelled IDO
    event RefundWhenCancelled(
        uint256 indexed idoId, 
        address indexed user, 
        uint256 amount
    );


    // ======================= Modifier & Constructor ======================
    /// @notice Modifier to ensure the IDO ID is valid
    modifier idoIdExists(uint256 idoId) {
        _idoIdExists(idoId);
        _;
    }

    /// @dev Internal check for IDO ID existence to reduce code size
    function _idoIdExists(uint256 idoId) internal view {
        require(idoId > 0 && idoId < nextIdoId, "IDO: invalid ID");
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the IDO contract
    /// @param _paymentToken The address of the payment token (USDC)
    /// @param _multionesAccess The address of the AccessControl contract
    function initialize(
        address _paymentToken,
        address _multionesAccess
    ) public initializer {
        require(_paymentToken != address(0), "IDO: zero address");
        require(_multionesAccess != address(0), "IDO: zero address");

        paymentToken = IERC20(_paymentToken);
        multionesAccess = IMultiOnesAccess(_multionesAccess);
        
        nextIdoId = 1;       // Start from ID 1
    }


    // ========================= Internal functions ========================
    /// @notice Authorizes the upgrade of the contract implementation
    function _authorizeUpgrade(address /*newImplementation*/) internal override onlyOwner {}


    // =========================== Admin Functions =========================
    /// @notice Creates a new IDO
    /// @param saleToken The RWA token address to be sold
    /// @param targetRaiseAmount The amount of payment tokens to raise
    /// @param startTime The start timestamp of the IDO
    /// @param endTime The end timestamp of the IDO
    /// @return The ID of the newly created IDO
    function createIdo(
        address saleToken,
        uint256 targetRaiseAmount,
        uint64 startTime,
        uint64 endTime
    ) public onlyOwner returns (uint256) {
        // Check parameters
        require(saleToken != address(0), "IDO: zero address");
        require(targetRaiseAmount > 0, "IDO: zero target raise amount");
        require(startTime > block.timestamp, "IDO: start in past");
        require(endTime > startTime, "IDO: invalid times");

        // Update state variables
        uint256 idoId = nextIdoId++;
        idoInfos[idoId] = IdoInfo({
            saleToken: IERC20(saleToken),
            totalSaleAmount: 0, // to be updated when deposit RWA
            targetRaiseAmount: targetRaiseAmount,
            startTime: startTime,
            endTime: endTime,
            totalRaised: 0,
            adminStatus: AdminStatus.Active
        });

        // Event
        emit IDOCreated(
            idoId, saleToken, targetRaiseAmount, startTime, endTime
        );
        return idoId;
    }

    /// @notice Updates the start and end times of an IDO
    /// @dev Can only change `endTime` after IDO begins
    /// @param idoId The ID of the IDO
    /// @param newStartTime The new start timestamp
    /// @param newEndTime The new end timestamp
    function updateIdoTimes(
        uint256 idoId, 
        uint64 newStartTime, 
        uint64 newEndTime
    ) public onlyOwner idoIdExists(idoId) {
        // Check time range
        IdoInfo storage info = idoInfos[idoId];
        uint64 startTime = info.startTime;
        uint64 endTime = info.endTime;

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

    /// @notice Cancels an IDO
    /// @dev Only allowed before IDO starts
    /// @param idoId The ID of the IDO
    function cancelIdo(
        uint256 idoId
    ) public onlyOwner idoIdExists(idoId) {
        // Check time range
        IdoInfo storage info = idoInfos[idoId];
        require(block.timestamp < info.startTime, "IDO: already started");
        require(info.adminStatus == AdminStatus.Active, "IDO: wrong status");

        // Update state variables
        info.adminStatus = AdminStatus.Cancelled;

        // Event
        emit IDOCancelled(idoId);
    }

    /// @notice Withdraws the raised funds to the teller
    /// @param idoId The ID of the IDO
    function withdrawFunds(
        uint256 idoId
    ) public onlyTeller idoIdExists(idoId) {
        // Check time range & withdrawal status
        IdoInfo storage info = idoInfos[idoId];
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

    /// @notice Deposits RWA tokens for distribution
    /// @param idoId The ID of the IDO
    /// @param rwaAmount The amount of RWA tokens to deposit
    function depositRwa(
        uint256 idoId,
        uint256 rwaAmount
    ) public onlyTeller idoIdExists(idoId) {
        // Check time range & withdrawal status
        IdoInfo storage info = idoInfos[idoId];
        require(block.timestamp > info.endTime, "IDO: not ended");
        require(
            info.adminStatus == AdminStatus.Withdrawn, 
            "IDO: funds not withdrawn or RWA already deposited"
        );
        require(rwaAmount > 0, "IDO: zero RWA amount");

        // Update state, transfer token
        info.totalSaleAmount = rwaAmount;
        info.adminStatus = AdminStatus.Settled;
        info.saleToken.safeTransferFrom(msg.sender, address(this), rwaAmount);

        // Event
        emit AdminRwaDeposited(idoId, rwaAmount);
    }

    /// @notice Enables users to claim their tokens
    /// @param idoId The ID of the IDO
    function allowClaim(
        uint256 idoId
    ) public onlyTeller idoIdExists(idoId) {
        IdoInfo storage info = idoInfos[idoId];
        require(info.adminStatus == AdminStatus.Settled, "IDO: RWA not deposited");
        info.adminStatus = AdminStatus.ClaimAllowed;
        emit AdminClaimAllowed(idoId);
    }


    // =========================== User Functions ==========================
    /// @notice Subscribes to an IDO with payment tokens
    /// @param idoId The ID of the IDO
    /// @param amount The amount of payment tokens to subscribe
    function subscribe(
        uint256 idoId, 
        uint256 amount
    ) public idoIdExists(idoId) {
        // Check parameters
        require(amount > 0, "IDO: zero amount");

        // Check time range
        IdoInfo storage info = idoInfos[idoId];
        require(info.adminStatus != AdminStatus.Cancelled, "IDO: cancelled");
        require(block.timestamp >= info.startTime, "IDO: not started");
        require(block.timestamp <= info.endTime, "IDO: ended");

        // Update state variables
        userInfo[idoId][msg.sender].subscribedAmount += amount;
        info.totalRaised += amount;

        // Transfer payment token
        paymentToken.safeTransferFrom(msg.sender, address(this), amount);

        // Event
        emit Subscribed(idoId, msg.sender, amount);
    }

    /// @notice Claims RWA tokens and/or refund after IDO ends
    /// @param idoId The ID of the IDO
    function claim(uint256 idoId) public idoIdExists(idoId) {
        IdoInfo storage info = idoInfos[idoId];
        UserInfo storage user = userInfo[idoId][msg.sender];
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
            refundAmount = 0;
        } else {
            // Over-subscribed: ProRate
            uint256 cost = subscribedAmount.mulDiv(info.targetRaiseAmount, info.totalRaised);
            refundAmount = subscribedAmount - cost;
        }

        if (info.totalRaised > 0) {
            rwaAmount = subscribedAmount.mulDiv(info.totalSaleAmount, info.totalRaised);
        } else {
            rwaAmount = 0;
        }

        // Distribute token and refund
        info.saleToken.safeTransfer(msg.sender, rwaAmount);
        if (refundAmount > 0) {
            paymentToken.safeTransfer(msg.sender, refundAmount);
        }

        // Event
        emit Claimed(idoId, msg.sender, rwaAmount, refundAmount);
    }

    /// @notice Refunds subscription if the IDO is cancelled
    /// @param idoId The ID of the IDO
    function refundWhenCancelled(uint256 idoId) public idoIdExists(idoId) {
        // Check conditions
        IdoInfo storage info = idoInfos[idoId];
        UserInfo storage user = userInfo[idoId][msg.sender];
        uint256 subscribedAmount = user.subscribedAmount;

        require(info.adminStatus == AdminStatus.Cancelled, "IDO: not cancelled");
        require(!user.claimed, "IDO: already claimed");
        require(subscribedAmount > 0, "IDO: no subscription");

        // Update state
        user.claimed = true;
        
        // Refund full amount
        paymentToken.safeTransfer(msg.sender, subscribedAmount);
        
        emit RefundWhenCancelled(idoId, msg.sender, subscribedAmount);
    }


    // =========================== View Functions ==========================
    /// @notice Returns the information of a specific IDO
    /// @param idoId The ID of the IDO
    /// @return The IdoInfo struct
    function getIdoInfo(uint256 idoId) public view returns (IdoInfo memory) {
        return idoInfos[idoId];
    }

    /// @notice Returns the participation information of a user in a specific IDO
    /// @param idoId The ID of the IDO
    /// @param user The address of the user
    /// @return The UserInfo struct
    function getUserInfo(uint256 idoId, address user) public view returns (UserInfo memory) {
        return userInfo[idoId][user];
    }

    /// @notice Checks if an IDO is currently open for subscription
    /// @param idoId The ID of the IDO
    /// @return True if the IDO is active and within the time range
    function isOpen(uint256 idoId) public view returns (bool) {
        IdoInfo storage info = idoInfos[idoId];
        return (
            info.adminStatus == AdminStatus.Active &&
            block.timestamp >= info.startTime &&
            block.timestamp <= info.endTime
        );
    }


    // =========================== Storage Gap =============================
    uint256[50] private _gap;
}
