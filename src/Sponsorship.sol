// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";
import "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

enum IdoStatus {
    ACTIVE,
    INACTIVE,
    FINISHED
}

struct IdoEvent {
    bytes32 id;
    string name;
    string uuid;
    uint256 minTicketSize;
    uint256 maxTicketSize;
    uint256 createdAt;
    uint256 updatedAt;
    uint256 sponsorStartAt;
    uint256 sponsorEndAt;
    uint256 reservedTotal;
    uint256 allocationTotal;
    address fundReceiverAddress;
    uint256 maxOffersReceiverCanAccept;
    IdoStatus status;
}

enum OfferStatus {
    PROPOSAL, // offer is sent, sponsor's collateral is locked, waiting gamer to confirm (accept or reject)
    ACCEPTED, // offer is accepted by gamer
    REJECTED, // offer is rejected by gamer (collateral is unlocked and return back to sponsor)
    CANCELED, // offer is first accepted by gamer but then canceled by sponsor (collateral is unlocked and return back to sponsor)
    COMPLETED, // ido's result is announced and the offer is in the WINNER list, collateral is getting swap with IDO allocation
    REFUNDED // ido's result is announced and the offer is not in the WINNER list, collateral is unlocked and return back to sponsor
}

struct SponsorOffer {
    uint256 id;
    address sender;
    address receiver;
    bytes32 idoId;
    string idoUuid;
    uint256 ticketSize;
    uint256 sponsorAmount;
    OfferStatus status;
    uint256 createdAt;
    uint256 updatedAt;
}

contract CollateralVault is ReentrancyGuard {
    IERC20 public USDT_TOKEN;
    mapping(address account => uint256 amount) balance;
    mapping(address account => mapping(uint256 reason => uint256 amount)) spent;

    event CollateralDeposited(address indexed depositor, uint256 amount);
    event CollateralWithdrew(address indexed depositor, uint256 amount);

    constructor(address tokenAddress_) {
        USDT_TOKEN = IERC20(tokenAddress_);
    }

    function depositCollateral(uint256 amount_) public virtual nonReentrant {
        address depositor = msg.sender;
        require(
            USDT_TOKEN.balanceOf(depositor) >= amount_,
            "Insufficient USD token balance"
        );
        require(
            USDT_TOKEN.allowance(depositor, address(this)) >= amount_,
            "Insufficient USD token spending allowance"
        );
        balance[depositor] += amount_;
        bool success = USDT_TOKEN.transferFrom(
            depositor,
            address(this),
            amount_
        );
        if (!success) {
            revert("USD transfer failed");
        }
        emit CollateralDeposited(depositor, amount_);
    }

    function withdrawCollateral(uint256 amount_) public virtual nonReentrant {
        address depositor = msg.sender;
        uint256 _balance = balance[depositor];
        require(amount_ > 0, "Zero amount withdrawal is not allowed");
        require(_balance >= amount_, "Withdraw amount greater than balance");
        balance[depositor] -= amount_;
        bool success = USDT_TOKEN.transfer(depositor, amount_);
        if (!success) {
            revert("USD transfer failed");
        }
        emit CollateralWithdrew(depositor, amount_);
    }

    function _spend(
        address account_,
        uint256 reason_,
        uint256 amount_
    ) internal {
        require(amount_ > 0, "Zero amount spend is not possible");
        require(balance[account_] >= amount_, "Insufficient balance to spend");
        balance[account_] -= amount_;
        spent[account_][reason_] += amount_;
    }

    function _refund(address account_, uint256 reason_) internal {
        uint256 amount = spent[account_][reason_];
        require(amount > 0, "Zero refund amount is not possible");
        spent[account_][reason_] = 0;
        balance[account_] += amount;
    }

    function getBalance(address account_) public view returns (uint256) {
        return balance[account_];
    }
}

contract Sponsorship is
    Pausable,
    CollateralVault,
    Multicall,
    AccessControlEnumerable
{
    using EnumerableSet for EnumerableSet.UintSet;
    using Strings for string;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    mapping(uint256 offerId => SponsorOffer) sponsorOfferMap;
    mapping(bytes32 idoId => IdoEvent) idoEventMap;
    mapping(address receiver => mapping(bytes32 idoId => uint256 count)) acceptedOffersByReceiver;
    // the (enumerable) list of offer IDs the sponsor has made
    mapping(address sender => EnumerableSet.UintSet offerIdList) offerIdListBySender;
    // the (enumerable) list of offer IDs belong to the IDO
    mapping(bytes32 idoId => EnumerableSet.UintSet offerIdList) offerIdListByIdo;
    // the (enumerable) list of offer IDs that is winning the IDO
    mapping(bytes32 idoId => EnumerableSet.UintSet offerIdList) winningOfferIdListByIdo;
    // keep track of the active offer ID the sponsor has sent to a gamer
    // for each ido, a sponsor can only has upto 01 active offer to each gamer
    // an active offer mean its status is one of PROPOSAL | ACCEPTED | COMPLETED | REFUNDED
    mapping(bytes32 idoId => mapping(address sender => mapping(address receiver => uint256 offerId))) offerRelationship;
    // the offerId will never be zero
    uint256 public offerIdCounter = 0;

    constructor(address usdTokenAddress_) CollateralVault(usdTokenAddress_) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        addIdoEvent(
            "c6f5606d-0977-450b-b6f7-1b8bc41ebd7b",
            "Meme Fighter",
            1,
            1000_000_000, // 1k$
            1000_000_000, // 1k$
            1711238400, // 24 Mar
            1713744000, // 22 Apr
            0,
            0x6666987Fd0D3ECB20d6fF38EcB3f4cab1BdE48b7
        );
        addIdoEvent(
            "8d9f37cb-bb72-48a5-abd7-41757fc86904",
            "Ancient Ape Adventures",
            1,
            1000_000_000, // 1k$
            1000_000_000, // 1k$
            1713744000, // 22 Apr
            1714348800, // 29 Apr
            0,
            0x6666987Fd0D3ECB20d6fF38EcB3f4cab1BdE48b7
        );
    }

    event OfferCreated(
        bytes32 indexed idoId,
        uint256 indexed offerId,
        address indexed sender,
        address receiver,
        uint256 ticketSize,
        uint256 sponsorAmount
    );
    event OfferAccepted(uint256 offerId);
    event OfferCanceled(uint256 offerId);
    event OfferRejected(uint256 offerId);
    event IdoEventAdded(bytes32 idoId);
    event IdoEventUpdated(bytes32 idoId);
    event IdoStatusUpdated(bytes32 idoId, IdoStatus status);

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "ADMIN_ROLE is required");
        _;
    }

    function pause() public onlyAdmin {
        _pause();
    }

    function unpause() public onlyAdmin {
        _unpause();
    }

    //###################################################
    // Region: INTERNAL
    //###################################################

    /**
     * @dev lock collateral when making offer
     */
    function _lockCollateral(uint256 offerId) internal {
        SponsorOffer memory offerObject = sponsorOfferMap[offerId];
        _spend(
            offerObject.sender,
            offerId,
            offerObject.ticketSize + offerObject.sponsorAmount
        );
    }

    /**
     * @dev unlock collateral when offer is refunded or invalid for whatever reason
     */
    function _unlockCollateral(uint256 offerId) internal {
        SponsorOffer memory offerObject = sponsorOfferMap[offerId];
        address sender = offerObject.sender;
        _refund(sender, offerId);
    }

    /**
     * @dev mark the offer as ACCEPTED and do post actions
     */
    function _acceptOffer(uint256 offerId) internal {
        address receiver = sponsorOfferMap[offerId].receiver;
        bytes32 idoId = sponsorOfferMap[offerId].idoId;
        sponsorOfferMap[offerId].status = OfferStatus.ACCEPTED;
        sponsorOfferMap[offerId].updatedAt = getEpoch();
        acceptedOffersByReceiver[receiver][idoId] += 1;
        idoEventMap[idoId].reservedTotal += sponsorOfferMap[offerId].ticketSize;
        if (
            acceptedOffersByReceiver[receiver][idoId] >
            idoEventMap[idoId].maxOffersReceiverCanAccept
        ) {
            revert(
                "The receiver has reached the maximum number of accepted offers"
            );
        }
        if (
            idoEventMap[idoId].allocationTotal > 0 &&
            idoEventMap[idoId].reservedTotal >
            idoEventMap[idoId].allocationTotal
        ) {
            revert("Global IDO allocation amount has been reached");
        }
        emit OfferAccepted(offerId);
    }

    /**
     * @dev mark the offer as REJECTED, release collateral and do post actions
     */
    function _rejectOffer(uint256 offerId) internal {
        bytes32 idoId = sponsorOfferMap[offerId].idoId;
        address sender = sponsorOfferMap[offerId].sender;
        address receiver = sponsorOfferMap[offerId].receiver;
        sponsorOfferMap[offerId].status = OfferStatus.REJECTED;
        sponsorOfferMap[offerId].updatedAt = getEpoch();
        offerRelationship[idoId][sender][receiver] = 0;
        _unlockCollateral(offerId);
        emit OfferRejected(offerId);
    }

    /**
     * @dev mark the offer as CANCELED, return collateral and do post actions
     */
    function _cancelOffer(uint256 offerId) internal {
        bytes32 idoId = sponsorOfferMap[offerId].idoId;
        address sender = sponsorOfferMap[offerId].sender;
        address receiver = sponsorOfferMap[offerId].receiver;
        sponsorOfferMap[offerId].status = OfferStatus.CANCELED;
        sponsorOfferMap[offerId].updatedAt = getEpoch();
        offerRelationship[idoId][sender][receiver] = 0;
        _unlockCollateral(offerId);
        emit OfferCanceled(offerId);
    }

    function _assertIdoEvent(bytes32 idoId) internal {
        IdoEvent storage ido = idoEventMap[idoId];
        if (ido.name.equal("")) {
            revert("Requirement: name is not empty");
        }
        if (ido.minTicketSize == 0) {
            revert("Requirement: minTicketSize > 0");
        }
        if (ido.maxTicketSize == 0) {
            ido.maxTicketSize = type(uint256).max;
        }
        if (ido.maxTicketSize < ido.minTicketSize) {
            revert("Requirement: maxTicketSize >= minTicketSize");
        }
        if (ido.fundReceiverAddress == address(0)) {
            revert("Requirement: fundReceiverAddress != null");
        }
        if (ido.sponsorEndAt < ido.sponsorStartAt) {
            revert("Requirement: sponsorEndAt >= sponsorStartAt");
        }
    }

    //###################################################
    // Region: PUBLIC WRITE
    //###################################################

    /**
     * @dev allow sponsor to make an offer
     */
    function createOffer(
        bytes32 idoId,
        address receiver,
        uint256 ticketSize,
        uint256 sponsorAmount
    ) public whenNotPaused returns (uint256) {
        uint256 offerId = ++offerIdCounter;
        address sender = msg.sender;
        IdoEvent memory ido = idoEventMap[idoId];
        require(ido.createdAt > 0, "The IDO does not exist");
        require(receiver != address(0), "Receiver can not be null address");
        require(offerRelationship[idoId][sender][receiver] == 0);
        require(
            ticketSize >= ido.minTicketSize && ticketSize <= ido.maxTicketSize,
            "The ticket size param is missing or invalid"
        );
        require(
            getEpoch() >= ido.sponsorStartAt,
            "Sponsoring is not yet allowed for this IDO"
        );
        require(
            getEpoch() < ido.sponsorEndAt,
            "Sponsoring is no longer available for this IDO"
        );
        require(
            ido.status == IdoStatus.ACTIVE,
            "The IDO is not currently active"
        );
        sponsorOfferMap[offerId] = SponsorOffer({
            id: offerId,
            sender: sender,
            receiver: receiver,
            idoId: idoId,
            idoUuid: ido.uuid,
            ticketSize: ticketSize,
            sponsorAmount: sponsorAmount,
            status: OfferStatus.PROPOSAL,
            createdAt: block.timestamp,
            updatedAt: block.timestamp
        });
        _lockCollateral(offerId);
        offerIdListByIdo[idoId].add(offerId);
        offerIdListBySender[sender].add(offerId);
        offerRelationship[idoId][sender][receiver] = offerId;
        emit OfferCreated(
            idoId,
            offerId,
            sender,
            receiver,
            ticketSize,
            sponsorAmount
        );
        // auto accept the offer if this is self-sponsor offer
        if (sender == receiver) {
            _acceptOffer(offerId);
        }
        return offerId;
    }

    /**
     * @dev allow gamer to accept the offer
     */
    function acceptOffer(uint256 offerId) public whenNotPaused {
        address caller = msg.sender;
        require(
            sponsorOfferMap[offerId].receiver == caller,
            "The offer is not being sent to the caller"
        );
        require(
            sponsorOfferMap[offerId].status == OfferStatus.PROPOSAL,
            "The offer is no longer in the PROPOSAL status"
        );
        bytes32 idoId = sponsorOfferMap[offerId].idoId;
        require(
            getEpoch() < idoEventMap[idoId].sponsorEndAt,
            "The IDO sponsoring period has ended"
        );
        require(
            idoEventMap[idoId].status == IdoStatus.ACTIVE,
            "The IDO is not currently active"
        );
        _acceptOffer(offerId);
    }

    /**
     * @dev allow gamer to reject the offer and return collateral to sponsor
     */
    function rejectOffer(uint256 offerId) public whenNotPaused {
        address caller = msg.sender;
        require(
            sponsorOfferMap[offerId].receiver == caller,
            "The offer is not being sent to caller"
        );
        require(
            sponsorOfferMap[offerId].status == OfferStatus.PROPOSAL,
            "Rejecting this offer is no longer possible"
        );
        bytes32 idoId = sponsorOfferMap[offerId].idoId;
        require(
            getEpoch() < idoEventMap[idoId].sponsorEndAt,
            "The IDO sponsoring period has ended"
        );
        require(
            idoEventMap[idoId].status == IdoStatus.ACTIVE,
            "The IDO is not currently active"
        );
        _rejectOffer(offerId);
    }

    /**
     * @dev allow the sponsor to cancel the PROPOSAL offer
     */
    function cancelOffer(uint256 offerId) public whenNotPaused {
        address caller = msg.sender;
        require(
            sponsorOfferMap[offerId].sender == caller,
            "Offer is not sent from caller"
        );
        bytes32 idoId = sponsorOfferMap[offerId].idoId;
        uint256 epoch = getEpoch();
        require(
            epoch < idoEventMap[idoId].sponsorEndAt,
            "The IDO sponsoring period has ended"
        );
        require(
            sponsorOfferMap[offerId].status == OfferStatus.PROPOSAL,
            "Canceling offer is no longer possible"
        );
        require(
            idoEventMap[idoId].status == IdoStatus.ACTIVE,
            "The IDO is not currently active"
        );
        _cancelOffer(offerId);
    }

    function refreshOfferStatus(uint256 offerId) public whenNotPaused {
        bytes32 idoId = sponsorOfferMap[offerId].idoId;
        if (idoEventMap[idoId].status != IdoStatus.FINISHED) {
            return;
        }
        if (winningOfferIdListByIdo[idoId].contains(offerId)) {
            sponsorOfferMap[offerId].status = OfferStatus.COMPLETED;
        } else {
            if (sponsorOfferMap[offerId].status == OfferStatus.ACCEPTED) {
                sponsorOfferMap[offerId].status = OfferStatus.REFUNDED;
                _unlockCollateral(offerId);
            }
            if (sponsorOfferMap[offerId].status == OfferStatus.PROPOSAL) {
                sponsorOfferMap[offerId].status = OfferStatus.CANCELED;
                _unlockCollateral(offerId);
            }
        }
    }

    function refreshOffersStatus(uint256[] calldata offerIdList) public {
        for (uint256 i = 0; i < offerIdList.length; i++) {
            refreshOfferStatus(offerIdList[i]);
        }
    }

    function depositCollateral(uint256 amount_) public override whenNotPaused {
        super.depositCollateral(amount_);
    }

    function withdrawCollateral(uint256 amount_) public override whenNotPaused {
        super.withdrawCollateral(amount_);
    }

    //###################################################
    // Region: ADMIN WRITE
    //###################################################

    /**
     * @dev allow ADMIN to add an IDO event
     */
    function addIdoEvent(
        string memory idoUuid,
        string memory name,
        uint256 maxOffersReceiverCanAccept,
        uint256 minTicketSize,
        uint256 maxTicketSize,
        uint256 sponsorStartAt,
        uint256 sponsorEndAt,
        uint256 allocationTotal,
        address fundReceiverAddress
    ) public onlyAdmin {
        bytes32 idoId = keccak256(abi.encodePacked(idoUuid));
        require(idoEventMap[idoId].createdAt == 0, "The IDO already exists");
        uint256 epoch = getEpoch();
        idoEventMap[idoId] = IdoEvent({
            id: idoId,
            name: name,
            uuid: idoUuid,
            maxOffersReceiverCanAccept: maxOffersReceiverCanAccept,
            minTicketSize: minTicketSize,
            maxTicketSize: maxTicketSize,
            sponsorStartAt: sponsorStartAt,
            sponsorEndAt: sponsorEndAt,
            reservedTotal: 0,
            allocationTotal: allocationTotal,
            fundReceiverAddress: fundReceiverAddress,
            createdAt: epoch,
            updatedAt: epoch,
            status: IdoStatus.ACTIVE
        });
        _assertIdoEvent(idoId);
        emit IdoEventAdded(idoId);
    }

    /**
     * @dev allow ADMIN to update the IDO event
     */
    function updateIdoEvent(
        bytes32 idoId,
        string memory name,
        uint256 maxOffersReceiverCanAccept,
        uint256 minTicketSize,
        uint256 maxTicketSize,
        uint256 sponsorStartAt,
        uint256 sponsorEndAt,
        uint256 allocationTotal,
        address fundReceiverAddress
    ) public onlyAdmin {
        require(idoEventMap[idoId].createdAt > 0, "The IDO does not exist");
        uint256 epoch = getEpoch();
        idoEventMap[idoId] = IdoEvent({
            id: idoId,
            name: name,
            uuid: idoEventMap[idoId].uuid,
            maxOffersReceiverCanAccept: maxOffersReceiverCanAccept,
            minTicketSize: minTicketSize,
            maxTicketSize: maxTicketSize,
            sponsorStartAt: sponsorStartAt,
            sponsorEndAt: sponsorEndAt,
            reservedTotal: idoEventMap[idoId].reservedTotal,
            allocationTotal: allocationTotal,
            fundReceiverAddress: fundReceiverAddress,
            createdAt: idoEventMap[idoId].createdAt,
            updatedAt: epoch,
            status: idoEventMap[idoId].status
        });
        _assertIdoEvent(idoId);
        emit IdoEventUpdated(idoId);
    }

    function setIdoStatus(bytes32 idoId, IdoStatus status) public onlyAdmin {
        require(idoEventMap[idoId].createdAt > 0, "The IDO does not exist");
        require(idoEventMap[idoId].status != IdoStatus.FINISHED);
        idoEventMap[idoId].status = status;
        emit IdoStatusUpdated(idoId, status);
    }

    /**
     * @dev allow ADMIN to append winning offer IDs
     * - collaterals will be transfered to fund receiver
     * - sponsor amount will be transfered to gamer
     * - need to call `setIdoStatus(COMPLETED)` after this, otherwise `refreshOffersStatus` won't work
     */
    function addIdoWinningOffers(
        bytes32 idoId,
        uint256[] memory winningOfferIdList
    ) public onlyAdmin {
        require(
            getEpoch() >= idoEventMap[idoId].sponsorEndAt,
            "The IDO sponsoring period has not ended"
        );
        require(
            idoEventMap[idoId].status != IdoStatus.FINISHED,
            "The IDO has finished"
        );
        uint256 length = winningOfferIdList.length;
        require(length > 0, "Requirement: winningOfferIdList.length > 0");
        uint256 totalCollateralAmount = 0;
        for (uint256 i = 0; i < length; i++) {
            uint256 offerId = winningOfferIdList[i];
            if (sponsorOfferMap[offerId].idoId != idoId) {
                continue;
            }
            winningOfferIdListByIdo[idoId].add(offerId);
            totalCollateralAmount += sponsorOfferMap[offerId].ticketSize;
            bool success = USDT_TOKEN.transfer(
                sponsorOfferMap[offerId].receiver,
                sponsorOfferMap[offerId].sponsorAmount
            );
            if (!success) {
                revert("USD transfer failed");
            }
        }
        bool _success = USDT_TOKEN.transfer(
            idoEventMap[idoId].fundReceiverAddress,
            totalCollateralAmount
        );
        if (!_success) {
            revert("USD transfer failed");
        }
    }

    //###################################################
    // Region: PUBLIC READ
    //###################################################

    function getIdoWinningOffers(
        bytes32 idoId
    ) public view returns (uint256[] memory) {
        return winningOfferIdListByIdo[idoId].values();
    }

    function getOfferBetween(
        address sender,
        address receiver,
        bytes32 idoId
    ) public view returns (uint256) {
        return offerRelationship[idoId][sender][receiver];
    }

    function getOffer(
        uint256 offerId
    ) public view returns (SponsorOffer memory) {
        return sponsorOfferMap[offerId];
    }

    function getOffers(
        uint256[] memory offerIdList
    ) public view returns (SponsorOffer[] memory offerList) {
        uint256 length = offerIdList.length == 0
            ? offerIdCounter
            : offerIdList.length;
        offerList = new SponsorOffer[](length);
        if (length == 0) return offerList;
        for (uint256 i = 0; i < length; i++) {
            offerList[i] = getOffer(
                offerIdList.length == 0 ? i + 1 : offerIdList[i]
            );
        }
    }

    function getIdo(bytes32 idoId) public view returns (IdoEvent memory) {
        return idoEventMap[idoId];
    }

    function getIdos(
        bytes32[] memory idoIdList
    ) public view returns (IdoEvent[] memory idoList) {
        uint256 length = idoIdList.length;
        idoList = new IdoEvent[](length);
        for (uint256 i = 0; i < length; i++) {
            idoList[i] = getIdo(idoIdList[i]);
        }
    }

    function getEpoch() public view returns (uint256) {
        return block.timestamp;
    }

    /**
     * @dev return the sum balance of collateral + locked collateral
     * WARNING: this is unsafe gas function
     */
    function getTotalCollateral(address user_) public view returns (uint256) {
        uint256 total = getBalance(user_);
        uint256[] memory offersMadeByUser = offerIdListBySender[user_].values();
        for (uint256 i = 0; i < offersMadeByUser.length; i++) {
            SponsorOffer memory offer = sponsorOfferMap[offersMadeByUser[i]];
            if (
                offer.status == OfferStatus.PROPOSAL ||
                offer.status == OfferStatus.ACCEPTED
            ) {
                total += offer.ticketSize + offer.sponsorAmount;
            }
        }
        return total;
    }

    /**
     * WARNING: this is unsafe gas function
     */
    function getTotalCollateralWithStatus(
        address user_,
        OfferStatus status_
    ) public view returns (uint256 totalCollateral) {
        uint256[] memory offersMadeByUser = offerIdListBySender[user_].values();
        for (uint256 i = 0; i < offersMadeByUser.length; i++) {
            SponsorOffer memory offer = sponsorOfferMap[offersMadeByUser[i]];
            if (offer.status == status_) {
                totalCollateral += offer.ticketSize;
            }
        }
    }

    /**
     * WARNING: this is unsafe gas function
     */
    function getTotalSponsorAmountWithStatus(
        address user_,
        OfferStatus status_
    ) public view returns (uint256 totalSponsorAmount) {
        uint256[] memory offersMadeByUser = offerIdListBySender[user_].values();
        for (uint256 i = 0; i < offersMadeByUser.length; i++) {
            SponsorOffer memory offer = sponsorOfferMap[offersMadeByUser[i]];
            if (offer.status == status_) {
                totalSponsorAmount += offer.sponsorAmount;
            }
        }
    }

    /**
     * WARNING: this is unsafe gas function
     */
    function getUserOffers(
        address user_
    ) public view returns (uint256[] memory) {
        return offerIdListBySender[user_].values();
    }
}
