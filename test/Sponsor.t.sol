// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import {Test, console} from "forge-std/Test.sol";
import {Sponsorship, IdoEvent, SponsorOffer, OfferStatus, IdoStatus} from "../src/Sponsorship.sol";
import {USDT} from "../src/USDT.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";

contract SponsorshipTest is Test {
    Sponsorship public sponsorInstance;
    USDT public usdtTokenInstance;

    address public admin = address(0xc0ffee); // admin
    address public user1 = address(0xff01);
    address public user2 = address(0xff02);
    address public user3 = address(0xff03);
    address public user4 = address(0xff04);
    address public user5 = address(0xff05);
    address public deadAddr = address(0xdead);

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // Meme Fighter IDO
    bytes32 public mfIdoId =
        keccak256(abi.encodePacked("c6f5606d-0977-450b-b6f7-1b8bc41ebd7b"));
    // Ancient Ape Adventures
    bytes32 public a3IdoId =
        keccak256(abi.encodePacked("8d9f37cb-bb72-48a5-abd7-41757fc86904"));

    function setUp() public {
        vm.startPrank(admin);
        usdtTokenInstance = new USDT();
        assertTrue(usdtTokenInstance.decimals() > 0);
        sponsorInstance = new Sponsorship(address(usdtTokenInstance));
        vm.stopPrank();
    }

    //###################################################
    // Region: INTERNAL
    //###################################################

    function _setBlockTimestamp(uint256 value) internal {
        rewind(block.timestamp);
        skip(value);
        assertTrue(block.timestamp == value);
    }

    function _createOffer(
        address sender_,
        address receiver_,
        bytes32 idoId_,
        uint256 ticketSize_,
        uint256 sponsorAmount_
    ) internal returns (uint256 offerId) {
        vm.prank(sender_);
        offerId = sponsorInstance.createOffer(
            idoId_,
            receiver_,
            ticketSize_,
            sponsorAmount_
        );
    }

    function _acceptOffer(uint256 offerId) internal {
        SponsorOffer memory offer = sponsorInstance.getOffer(offerId);
        vm.prank(offer.receiver);
        sponsorInstance.acceptOffer(offerId);
    }

    function _rejectOffer(uint256 offerId) internal {
        SponsorOffer memory offer = sponsorInstance.getOffer(offerId);
        vm.prank(offer.receiver);
        sponsorInstance.rejectOffer(offerId);
    }

    function _cancelOffer(uint256 offerId) internal {
        SponsorOffer memory offer = sponsorInstance.getOffer(offerId);
        vm.prank(offer.sender);
        sponsorInstance.cancelOffer(offerId);
    }

    function _setIdoStatus(bytes32 idoId, IdoStatus status) internal {
        vm.prank(admin);
        sponsorInstance.setIdoStatus(idoId, status);
    }

    function _faucetCollateral(address account_, uint256 amount_) internal {
        usdtTokenInstance.faucet(account_, amount_);
    }

    function _depositCollateral(address account_, uint256 amount_) internal {
        vm.prank(account_);
        sponsorInstance.depositCollateral(amount_);
    }

    function _faucetAndDepositCollateral(
        address account_,
        uint256 amount_
    ) internal {
        _faucetCollateral(account_, amount_);
        vm.prank(account_);
        usdtTokenInstance.approve(address(sponsorInstance), amount_);
        _depositCollateral(account_, amount_);
    }

    function _getAccountBalances(
        address account_
    ) public view returns (uint256, uint256) {
        uint256 erc20Balance = usdtTokenInstance.balanceOf(account_);
        uint256 collateralBalance = sponsorInstance.getBalance(account_);
        return (erc20Balance, collateralBalance);
    }

    function test_faucetAndDepositCollateral() internal {
        address account_ = user1;
        uint256 amount_ = 1000e6;
        assertTrue(amount_ > 0);
        uint256 userUsdBalanceBefore = usdtTokenInstance.balanceOf(account_);
        usdtTokenInstance.faucet(account_, amount_);
        uint256 userUsdBalanceAfter = usdtTokenInstance.balanceOf(account_);
        assertTrue(userUsdBalanceAfter == userUsdBalanceBefore + amount_);
        vm.prank(account_);
        usdtTokenInstance.approve(address(sponsorInstance), amount_);
        uint256 userCollateralBalanceAfter = sponsorInstance.getBalance(
            account_
        );
        vm.prank(account_);
        sponsorInstance.depositCollateral(amount_);
        uint256 userCollateralBalanceBefore = sponsorInstance.getBalance(
            account_
        );
        assertTrue(
            userCollateralBalanceBefore == userCollateralBalanceAfter + amount_
        );
    }

    //###################################################
    // Region: Main test cases
    //###################################################
    function test_adminRoleGranted() public {
        assertEq(sponsorInstance.hasRole(ADMIN_ROLE, address(this)), false);
        assertEq(sponsorInstance.hasRole(ADMIN_ROLE, admin), true);
        assertEq(sponsorInstance.hasRole(ADMIN_ROLE, user1), false);
        assertEq(sponsorInstance.hasRole(ADMIN_ROLE, user2), false);
        assertEq(sponsorInstance.hasRole(ADMIN_ROLE, user3), false);
        assertEq(sponsorInstance.hasRole(ADMIN_ROLE, user4), false);
    }

    function test_onlyAdminCanPauseAndUnpauseTheContract() public {
        assertEq(sponsorInstance.paused(), false);
        assertEq(sponsorInstance.hasRole(ADMIN_ROLE, user1), false);
        assertEq(sponsorInstance.hasRole(ADMIN_ROLE, admin), true);
        vm.expectRevert();
        vm.prank(user1);
        sponsorInstance.pause();
        vm.prank(admin);
        sponsorInstance.pause();
        assertEq(sponsorInstance.paused(), true);
        vm.expectRevert();
        vm.prank(user1);
        sponsorInstance.unpause();
        vm.prank(admin);
        sponsorInstance.unpause();
        assertEq(sponsorInstance.paused(), false);
    }

    function test_adminCanGrantAdminRole() public {
        assertEq(sponsorInstance.hasRole(ADMIN_ROLE, admin), true);
        assertEq(sponsorInstance.hasRole(ADMIN_ROLE, user5), false);
        vm.prank(admin);
        sponsorInstance.grantRole(ADMIN_ROLE, user5);
        assertEq(sponsorInstance.hasRole(ADMIN_ROLE, user5), true);

        uint256[] memory winningOfferIdList = new uint256[](1);
        IdoEvent memory ido = sponsorInstance.getIdo(mfIdoId);
        _setBlockTimestamp(ido.sponsorEndAt);
        vm.prank(user5);
        sponsorInstance.addIdoWinningOffers(mfIdoId, winningOfferIdList);
    }

    function test_multicall() public {
        assertEq(sponsorInstance.paused(), false);
        _faucetAndDepositCollateral(user1, 1010e6);
        IdoEvent memory mfIdo = sponsorInstance.getIdo(mfIdoId);
        _setBlockTimestamp(mfIdo.sponsorStartAt);
        vm.prank(user1);
        uint256 offerId = sponsorInstance.createOffer(mfIdoId, user2, 1000e6, 10e6);
        // test multicall with single calldata
        bytes[] memory callData = new bytes[](1);
        callData[0] = abi.encodeWithSignature("pause()");
        // @note multicall is delegate so original sender is kept
        vm.expectRevert();
        vm.prank(user1);
        sponsorInstance.multicall(callData);
        vm.prank(admin);
        sponsorInstance.multicall(callData);
        assertEq(sponsorInstance.paused(), true);
        // test multicall with multiple calldatas
        uint256[] memory winningOfferIdList = new uint256[](1);
        winningOfferIdList[0] = offerId;
        IdoEvent memory ido = sponsorInstance.getIdo(mfIdoId);
        _setBlockTimestamp(ido.sponsorEndAt);
        bytes[] memory callData1 = new bytes[](2);
        callData1[0] = abi.encodeWithSignature(
            "addIdoWinningOffers(bytes32,uint256[])",
            mfIdoId,
            winningOfferIdList
        );
        callData1[1] = abi.encodeWithSignature("unpause()");
        vm.prank(admin);
        sponsorInstance.multicall(callData1);
        assertEq(sponsorInstance.paused(), false);
        uint256[] memory idoResult = sponsorInstance.getIdoWinningOffers(
            mfIdoId
        );
        assertEq(idoResult.length, 1);
        assertEq(idoResult[0], offerId);
    }

    function test_onlyAdminCanAddAndUpdateIdoEvent() public {
        uint256 epoch = sponsorInstance.getEpoch();
        string memory idoName = "Forge";
        string memory idoUuid = "c666b8a8-636b-44b3-a6ad-d2145d3a115d";
        address idoFundReceiverAddress = address(0xc666b8a8);
        bytes32 idoId = keccak256(abi.encodePacked(idoUuid));
        IdoEvent memory ido = sponsorInstance.getIdo(idoId);
        assertEq(ido.createdAt, 0);
        vm.prank(user1);
        vm.expectRevert("ADMIN_ROLE is required");
        sponsorInstance.addIdoEvent(
            idoUuid,
            idoName,
            1,
            1000_000_000, // 1k$
            1000_000_000, // 1k$
            1711238400, // 24 Mar
            1713744000, // 22 Apr
            0,
            idoFundReceiverAddress
        );
        vm.prank(admin);
        sponsorInstance.addIdoEvent(
            idoUuid,
            idoName,
            1,
            1000_000_000, // 1k$
            1000_000_000, // 1k$
            1711238400, // 24 Mar
            1713744000, // 22 Apr
            0,
            idoFundReceiverAddress
        );
        ido = sponsorInstance.getIdo(idoId);
        assertTrue(ido.createdAt > 0 && ido.createdAt == epoch);
        assertTrue(ido.fundReceiverAddress == idoFundReceiverAddress);
        skip(180);
        address idoFundReceiverAddressUpdated = address(0xd2145d3a115d);
        vm.prank(user1);
        vm.expectRevert("ADMIN_ROLE is required");
        sponsorInstance.updateIdoEvent(
            idoId,
            "Forge X",
            1,
            2000_000_000, // 1k$
            2000_000_000, // 1k$
            2711238400, // 24 Mar
            2713744000, // 22 Apr
            10_000_000_000,
            idoFundReceiverAddressUpdated
        );
        vm.prank(admin);
        sponsorInstance.updateIdoEvent(
            idoId,
            "Forge X",
            1,
            2000_000_000, // 1k$
            2000_000_000, // 1k$
            2711238400, // 24 Mar
            2713744000, // 22 Apr
            10_000_000_000,
            idoFundReceiverAddressUpdated
        );
        ido = sponsorInstance.getIdo(idoId);
        assertTrue(ido.fundReceiverAddress == idoFundReceiverAddressUpdated);
    }

    function test_onlyAdminCanSetIdoResult() public {
        test_onlyAdminCanAddAndUpdateIdoEvent();
        IdoEvent memory ido = sponsorInstance.getIdo(mfIdoId);
        uint256[] memory winningOfferIdList = sponsorInstance
            .getIdoWinningOffers(mfIdoId);
        assertTrue(winningOfferIdList.length == 0);
        uint256 offerId = test_createOffer();
        winningOfferIdList = new uint256[](4);
        winningOfferIdList[0] = 33;
        winningOfferIdList[1] = offerId;
        winningOfferIdList[2] = 47;
        winningOfferIdList[3] = 86;
        _setBlockTimestamp(ido.sponsorEndAt);
        vm.expectRevert("ADMIN_ROLE is required");
        vm.prank(user2);
        sponsorInstance.addIdoWinningOffers(mfIdoId, winningOfferIdList);
        vm.prank(admin);
        sponsorInstance.addIdoWinningOffers(mfIdoId, winningOfferIdList);
        uint256[] memory winningOfferIdListActual = sponsorInstance
            .getIdoWinningOffers(mfIdoId);
        assertEq(winningOfferIdListActual.length == 1, true);
        // assertTrue(winningOfferIdListActual[0] == offerId);
    }

    // collateral deposit test
    function test_depositCollateral() public returns (uint256) {
        uint256 depositAmount = 100e6; // 100$
        vm.startPrank(user1);
        assert(usdtTokenInstance.balanceOf(user1) < depositAmount);
        vm.expectRevert(); // ERROR: not enough usdt balance
        sponsorInstance.depositCollateral(depositAmount);
        usdtTokenInstance.faucet(user1, depositAmount);
        uint256 addr1UsdtBalanceBefore = usdtTokenInstance.balanceOf(user1);
        uint256 vaultUsdtBalanceBefore = usdtTokenInstance.balanceOf(
            address(sponsorInstance)
        );
        uint256 vaultUsdtBalanceForAddr1Before = sponsorInstance.getBalance(
            user1
        );
        assert(addr1UsdtBalanceBefore >= depositAmount);
        vm.expectRevert(); // ERROR: no allowance
        sponsorInstance.depositCollateral(depositAmount);
        usdtTokenInstance.approve(address(sponsorInstance), depositAmount);
        sponsorInstance.depositCollateral(depositAmount);
        uint256 addr1UsdtBalanceAfter = usdtTokenInstance.balanceOf(user1);
        uint256 vaultUsdtBalanceAfter = usdtTokenInstance.balanceOf(
            address(sponsorInstance)
        );
        uint256 vaultUsdtBalanceForAddr1After = sponsorInstance.getBalance(
            user1
        );
        // check if fund is sent from addr1 to sponsorship address
        assert(addr1UsdtBalanceAfter == addr1UsdtBalanceBefore - depositAmount);
        assert(vaultUsdtBalanceAfter == vaultUsdtBalanceBefore + depositAmount);
        // vault's balance for this user should be reflected
        assert(
            vaultUsdtBalanceForAddr1After ==
                vaultUsdtBalanceForAddr1Before + depositAmount
        );
        vm.stopPrank();
        return depositAmount;
    }

    function test_withdrawCollateral() public {
        vm.startPrank(user1);
        vm.expectRevert("Withdraw amount greater than balance");
        sponsorInstance.withdrawCollateral(1);
        vm.stopPrank();
        uint256 depositAmount = test_depositCollateral();
        vm.startPrank(user1);
        vm.expectRevert("Withdraw amount greater than balance");
        sponsorInstance.withdrawCollateral(depositAmount + 1);
        vm.expectRevert("Zero amount withdrawal is not allowed");
        sponsorInstance.withdrawCollateral(0);
        uint256 addr1UsdtBalanceBefore = usdtTokenInstance.balanceOf(user1);
        uint256 vaultUsdtBalanceBefore = usdtTokenInstance.balanceOf(
            address(sponsorInstance)
        );
        uint256 vaultUsdtBalanceForAddr1Before = sponsorInstance.getBalance(
            user1
        );
        // # try withdraw 1/3 balance to see if it get reflected
        uint256 withdrawAmount = vaultUsdtBalanceForAddr1Before / 3;
        sponsorInstance.withdrawCollateral(withdrawAmount);
        // check if fund is sent from sponsorship address to addr1
        uint256 addr1UsdtBalanceAfter = usdtTokenInstance.balanceOf(user1);
        uint256 vaultUsdtBalanceAfter = usdtTokenInstance.balanceOf(
            address(sponsorInstance)
        );
        uint256 vaultUsdtBalanceForAddr1After = sponsorInstance.getBalance(
            user1
        );
        assert(
            addr1UsdtBalanceAfter == addr1UsdtBalanceBefore + withdrawAmount
        );
        assert(
            vaultUsdtBalanceAfter == vaultUsdtBalanceBefore - withdrawAmount
        );
        // vault's balance for this user should be reflected
        assert(
            vaultUsdtBalanceForAddr1After ==
                vaultUsdtBalanceForAddr1Before - withdrawAmount
        );
        // # try withdraw rest of balance to see if it get reflected
        vm.stopPrank();
    }

    function test_createOffer() public returns(uint256) {
        IdoEvent memory mfIdo = sponsorInstance.getIdo(mfIdoId);
        SponsorOffer memory offer;
        uint256 offerId;
        uint256 ticketSize = 1000e6; // 1k$
        uint256 sponsorAmount = 10e6; // 10$
        _faucetAndDepositCollateral(user1, ticketSize + sponsorAmount);
        (, uint256 user1CollateralBalance1) = _getAccountBalances(user1);
        // revert: can not create offer when sponsor period is not started
        vm.expectRevert("Sponsoring is not yet allowed for this IDO");
        vm.prank(user1);
        sponsorInstance.createOffer(mfIdoId, user2, ticketSize, sponsorAmount);
        // revert: can not create offer when sponsor period has ended
        vm.expectRevert("Sponsoring is no longer available for this IDO");
        _setBlockTimestamp(mfIdo.sponsorEndAt);
        vm.prank(user1);
        sponsorInstance.createOffer(mfIdoId, user2, ticketSize, sponsorAmount);
        // revert: can not create offer if collateral balance is not enough
        _setBlockTimestamp(mfIdo.sponsorStartAt);
        (, uint256 user2CollateralBalance1) = _getAccountBalances(user2);
        assertTrue(user2CollateralBalance1 < ticketSize);
        vm.expectRevert("Insufficient balance to spend");
        vm.prank(user2);
        sponsorInstance.createOffer(mfIdoId, user3, ticketSize, sponsorAmount);
        // revert: can not create offer if IDO is not active
        _setIdoStatus(mfIdoId, IdoStatus.INACTIVE);
        vm.expectRevert("The IDO is not currently active");
        vm.prank(user1);
        sponsorInstance.createOffer(mfIdoId, user2, ticketSize, sponsorAmount);
        _setIdoStatus(mfIdoId, IdoStatus.ACTIVE);
        // expect: can create offer when sponsor period has started and not ended
        _setBlockTimestamp(mfIdo.sponsorEndAt - 1);
        offerId = _createOffer(user1, user2, mfIdoId, ticketSize, sponsorAmount);
        offer = sponsorInstance.getOffer(offerId);
        assertTrue(offer.status == OfferStatus.PROPOSAL);
        (, uint256 user1CollateralBalance2) = _getAccountBalances(user1);
        assertTrue(
            user1CollateralBalance2 == user1CollateralBalance1 - ticketSize - sponsorAmount
        );
        return offerId;
    }

    function test_cancelOffer() public {
        IdoEvent memory mfIdo = sponsorInstance.getIdo(mfIdoId);
        SponsorOffer memory offer;
        uint256 ticketSize = 1000e6; // 1k$
        uint256 sponsorAmount = 10e6; // 10$

        // ## Scenario 1: cancel the PROPOSAL offer
        _faucetAndDepositCollateral(user1, ticketSize + sponsorAmount);
        _setBlockTimestamp(mfIdo.sponsorStartAt);
        (, uint256 user1CollateralBalance1) = _getAccountBalances(user1);
        uint256 offerId = _createOffer(
            user1,
            user2,
            mfIdoId,
            ticketSize,
            sponsorAmount
        );
        (, uint256 user1CollateralBalance2) = _getAccountBalances(user1);
        assertTrue(
            user1CollateralBalance2 ==
                user1CollateralBalance1 - ticketSize - sponsorAmount
        );
        assertTrue(
            offerId == sponsorInstance.getOfferBetween(user1, user2, mfIdoId)
        );
        // expect: can not cancel the offer if the sponsor period has passed
        _setBlockTimestamp(mfIdo.sponsorEndAt);
        vm.expectRevert("The IDO sponsoring period has ended");
        vm.prank(user1);
        sponsorInstance.cancelOffer(offerId);
        offer = sponsorInstance.getOffer(offerId);
        assertTrue(offer.status == OfferStatus.PROPOSAL);
        _setBlockTimestamp(mfIdo.sponsorEndAt - 1);
        // expect: can not cancel the offer if the IDO is not currently active
        _setIdoStatus(mfIdoId, IdoStatus.INACTIVE);
        vm.expectRevert("The IDO is not currently active");
        vm.prank(user1);
        sponsorInstance.cancelOffer(offerId);
        // expect: can cancel the offer if the offer is in PENDING status and current time is still in sponsor period
        _setIdoStatus(mfIdoId, IdoStatus.ACTIVE);
        vm.prank(user1);
        sponsorInstance.cancelOffer(offerId);
        (, uint256 user1CollateralBalance3) = _getAccountBalances(user1);
        assertTrue(
            user1CollateralBalance3 ==
                user1CollateralBalance2 + ticketSize + sponsorAmount
        );
        offer = sponsorInstance.getOffer(offerId);
        assertTrue(offer.status == OfferStatus.CANCELED);
        // expect: can not cancel the offer with status: CANCELED
        vm.expectRevert("Canceling offer is no longer possible");
        vm.prank(user1);
        sponsorInstance.cancelOffer(offerId);
    }

    function test_rejectOffer() public {
        IdoEvent memory mfIdo = sponsorInstance.getIdo(mfIdoId);
        SponsorOffer memory offer;
        uint256 ticketSize = 1000e6; // 1k$
        uint256 sponsorAmount = 10e6; // 10$

        _setBlockTimestamp(mfIdo.sponsorStartAt);
        _faucetAndDepositCollateral(user1, ticketSize + sponsorAmount);
        assertTrue(0 == sponsorInstance.getOfferBetween(user1, user2, mfIdoId));
        uint256 offerId = _createOffer(
            user1,
            user2,
            mfIdoId,
            ticketSize,
            sponsorAmount
        );
        assertTrue(
            offerId == sponsorInstance.getOfferBetween(user1, user2, mfIdoId)
        );
        (, uint256 user1CollateralBalance1) = _getAccountBalances(user1);
        // revert: the sender can not reject the offer
        vm.expectRevert("The offer is not being sent to caller");
        vm.prank(user1);
        sponsorInstance.rejectOffer(offerId);
        // revert: can not reject the offer if the IDO is not currently active
        _setIdoStatus(mfIdoId, IdoStatus.INACTIVE);
        vm.expectRevert("The IDO is not currently active");
        vm.prank(user2);
        sponsorInstance.rejectOffer(offerId);
        // revert: when sponsor period has passed, receiver can not reject the offer
        _setIdoStatus(mfIdoId, IdoStatus.ACTIVE);
        _setBlockTimestamp(mfIdo.sponsorEndAt);
        vm.expectRevert("The IDO sponsoring period has ended");
        vm.prank(user2);
        sponsorInstance.rejectOffer(offerId);
        // expect: receiver can reject the offer if the sponsor period has not passed yet
        _setBlockTimestamp(mfIdo.sponsorEndAt - 1);
        vm.prank(user2);
        sponsorInstance.rejectOffer(offerId);
        assertTrue(0 == sponsorInstance.getOfferBetween(user1, user2, mfIdoId));
        (, uint256 user1CollateralBalance2) = _getAccountBalances(user1);
        assertTrue(
            user1CollateralBalance2 ==
                user1CollateralBalance1 + ticketSize + sponsorAmount
        );
        offer = sponsorInstance.getOffer(offerId);
        assertEq(offer.status == OfferStatus.REJECTED, true);
        // revert: can not reject the rejected offer
        vm.expectRevert("Rejecting this offer is no longer possible");
        vm.prank(user2);
        sponsorInstance.rejectOffer(offerId);
    }

    function test_viewFn_getIdos() public {
        bytes32[] memory idoIdList = new bytes32[](3);
        idoIdList[0] = mfIdoId;
        idoIdList[1] = a3IdoId;
        idoIdList[2] = bytes32(keccak256(abi.encodePacked("rand-uuid")));
        IdoEvent[] memory idoList = sponsorInstance.getIdos(idoIdList);
        assertTrue(
            idoList[0].createdAt > 0 &&
                idoList[1].createdAt > 0 &&
                idoList[2].createdAt == 0
        );
    }

    function test_viewFn_collateralStats() public {
        uint256 total1 = sponsorInstance.getTotalCollateral(user1);
        assertTrue(total1 == 0);
        uint256 ticketSize = 1000e6;
        uint256 sponsorAmount = 10e6; // 10$
        uint256 depositAmount = ticketSize * 2 + sponsorAmount * 2;
        _faucetAndDepositCollateral(user1, depositAmount);
        (, uint256 collateralBalance2) = _getAccountBalances(user1);
        uint256 total2 = sponsorInstance.getTotalCollateral(user1);
        assertTrue(total2 == total1 + depositAmount);
        IdoEvent memory mfIdo = sponsorInstance.getIdo(mfIdoId);
        _setBlockTimestamp(mfIdo.sponsorStartAt);
        uint256 offer1 = _createOffer(
            user1,
            user2,
            mfIdoId,
            ticketSize,
            sponsorAmount
        );
        uint256 offer2 = _createOffer(
            user1,
            user3,
            mfIdoId,
            ticketSize,
            sponsorAmount
        );
        uint256 total3 = sponsorInstance.getTotalCollateral(user1);
        (, uint256 collateralBalance3) = _getAccountBalances(user1);
        assertTrue(
            total3 == total2 &&
                collateralBalance3 + depositAmount == collateralBalance2
        );
        assertTrue(
            total3 ==
                collateralBalance3 +
                    sponsorInstance.getTotalCollateralWithStatus(
                        user1,
                        OfferStatus.PROPOSAL
                    ) +
                    sponsorInstance.getTotalCollateralWithStatus(
                        user1,
                        OfferStatus.ACCEPTED
                    ) +
                    sponsorInstance.getTotalSponsorAmountWithStatus(
                        user1,
                        OfferStatus.PROPOSAL
                    ) +
                    sponsorInstance.getTotalSponsorAmountWithStatus(
                        user1,
                        OfferStatus.ACCEPTED
                    )
        );
        _acceptOffer(offer1);
        _rejectOffer(offer2);
        uint256 total4 = sponsorInstance.getTotalCollateral(user1);
        (, uint256 collateralBalance4) = _getAccountBalances(user1);
        assertTrue(
            total4 ==
                collateralBalance4 +
                    sponsorInstance.getTotalCollateralWithStatus(
                        user1,
                        OfferStatus.PROPOSAL
                    ) +
                    sponsorInstance.getTotalCollateralWithStatus(
                        user1,
                        OfferStatus.ACCEPTED
                    ) +
                    sponsorInstance.getTotalSponsorAmountWithStatus(
                        user1,
                        OfferStatus.PROPOSAL
                    ) +
                    sponsorInstance.getTotalSponsorAmountWithStatus(
                        user1,
                        OfferStatus.ACCEPTED
                    )
        );
    }

    function test_postIdo() public {
        // create some offers for the MF IDO
        IdoEvent memory mfIdo = sponsorInstance.getIdo(mfIdoId);
        SponsorOffer memory offer1;
        SponsorOffer memory offer2;
        SponsorOffer memory offer3;
        uint256 ticketSize = 1000e6; // 1k$
        uint256 sponsorAmount = 10e6; // 10$
        _faucetAndDepositCollateral(user1, ticketSize + sponsorAmount);
        _faucetAndDepositCollateral(user2, ticketSize + sponsorAmount);
        _faucetAndDepositCollateral(user3, ticketSize + sponsorAmount);
        _setBlockTimestamp(mfIdo.sponsorStartAt);
        uint256 offerId1 = _createOffer(user1, user2, mfIdoId, 1000e6, sponsorAmount); // this offer is non-winning
        _acceptOffer(offerId1);
        uint256 offerId2 = _createOffer(user2, user3, mfIdoId, 1000e6, sponsorAmount); // this offer is winning
        _acceptOffer(offerId2);
        uint256 offerId3 = _createOffer(user3, user4, mfIdoId, 1000e6, sponsorAmount); // this offer is not even getting accepted
        // close the MF IDO - only the 2nd offer is won
        _setBlockTimestamp(mfIdo.sponsorEndAt);
        uint256[] memory winningOfferIdList = new uint256[](1);
        winningOfferIdList[0] = offerId2;
        vm.prank(admin);
        sponsorInstance.addIdoWinningOffers(mfIdoId, winningOfferIdList);
        vm.prank(admin);
        sponsorInstance.setIdoStatus(mfIdoId, IdoStatus.FINISHED);
        // when offerId1 is non-winning, ANYONE can request a refund for it by refreshing offer status
        (, uint256 user1CollateralBalance1) = _getAccountBalances(user1);
        offer1 = sponsorInstance.getOffer(offerId1);
        assertTrue(offer1.status == OfferStatus.ACCEPTED);
        sponsorInstance.refreshOfferStatus(offerId1);
        offer1 = sponsorInstance.getOffer(offerId1);
        assertTrue(offer1.status == OfferStatus.REFUNDED);
        (, uint256 user1CollateralBalance2) = _getAccountBalances(user1);
        assertTrue(
            user1CollateralBalance2 == user1CollateralBalance1 + ticketSize + sponsorAmount
        );
        // offerId2 will be marked as COMPLETED and NOONE can request a refund for it
        offer2 = sponsorInstance.getOffer(offerId2);
        assertTrue(offer2.status == OfferStatus.ACCEPTED);
        sponsorInstance.refreshOffersStatus(winningOfferIdList);
        offer2 = sponsorInstance.getOffer(offerId2);
        assertTrue(offer2.status == OfferStatus.COMPLETED);
        // offerId3 will be marked as CANCELED and collateral is returned to sender
        (, uint256 user3CollateralBalance1) = _getAccountBalances(user3);
        offer3 = sponsorInstance.getOffer(offerId3);
        assertTrue(offer3.status == OfferStatus.PROPOSAL);
        sponsorInstance.refreshOfferStatus(offerId3);
        offer3 = sponsorInstance.getOffer(offerId3);
        assertTrue(offer3.status == OfferStatus.CANCELED);
        (, uint256 user3CollateralBalance2) = _getAccountBalances(user3);
        assertTrue(
            user3CollateralBalance2 == user3CollateralBalance1 + ticketSize + sponsorAmount
        );
    }

    function test_returnCollateralInEmergency() public {
        uint256 ticketSize = 1000e6;
        uint256 sponsorAmount = 10e6; // 10$
        _faucetAndDepositCollateral(user1, (ticketSize + sponsorAmount) * 2);
        _faucetAndDepositCollateral(user2, ticketSize + sponsorAmount);
        IdoEvent memory mfIdo = sponsorInstance.getIdo(mfIdoId);
        _setBlockTimestamp(mfIdo.sponsorStartAt);
        // create 3 offers with the 2nd offer is ACCEPTED status
        uint256 offerId1 = _createOffer(
            user1,
            user2,
            mfIdoId,
            ticketSize,
            sponsorAmount
        );
        uint256 offerId2 = _createOffer(
            user1,
            user3,
            mfIdoId,
            ticketSize,
            sponsorAmount
        );
        _acceptOffer(offerId2);
        uint256 offerId3 = _createOffer(
            user2,
            user3,
            mfIdoId,
            ticketSize,
            sponsorAmount
        );
        (, uint256 user1CollateralBalance1) = _getAccountBalances(user1);
        (, uint256 user2CollateralBalance1) = _getAccountBalances(user2);
        // on emergency, admin can return collateral to user by using `pause()` + `updateIdoEvent()` + `addIdoWinningOffers()` to [0] + `refreshOfferStatus(offerIdListByIdo)`
        _setBlockTimestamp(mfIdo.sponsorStartAt + 3599);
        uint256[] memory winningOfferIdList = new uint256[](1);
        winningOfferIdList[0] = 0;
        uint256[] memory offerIdToRefreshList = new uint256[](3);
        offerIdToRefreshList[0] = offerId1;
        offerIdToRefreshList[1] = offerId2;
        offerIdToRefreshList[2] = offerId3;
        bytes[] memory emergencyCallDataParams = new bytes[](5);

        emergencyCallDataParams[0] = abi.encodeWithSignature(
            "updateIdoEvent(bytes32,string,uint256,uint256,uint256,uint256,uint256,uint256,address)",
            mfIdo.id,
            mfIdo.name,
            mfIdo.maxOffersReceiverCanAccept,
            mfIdo.minTicketSize,
            mfIdo.maxTicketSize,
            mfIdo.sponsorStartAt,
            block.timestamp,
            mfIdo.allocationTotal,
            mfIdo.fundReceiverAddress
        );
        emergencyCallDataParams[1] = abi.encodeWithSignature(
            "addIdoWinningOffers(bytes32,uint256[])",
            mfIdoId,
            winningOfferIdList
        );
        emergencyCallDataParams[2] = abi.encodeWithSignature(
            "setIdoStatus(bytes32,uint8)",
            mfIdoId,
            IdoStatus.FINISHED
        );
        emergencyCallDataParams[3] = abi.encodeWithSignature(
            "refreshOffersStatus(uint256[])",
            offerIdToRefreshList
        );
        emergencyCallDataParams[4] = abi.encodeWithSignature("pause()");
        vm.prank(admin);
        sponsorInstance.multicall(emergencyCallDataParams);
        (, uint256 user1CollateralBalance2) = _getAccountBalances(user1);
        (, uint256 user2CollateralBalance2) = _getAccountBalances(user2);
        // confirm collateral is refuned to user1 and user2
        assertTrue(user1CollateralBalance2 == user1CollateralBalance1 + (ticketSize + sponsorAmount) * 2);
        assertTrue(user2CollateralBalance2 == user2CollateralBalance1 + (ticketSize + sponsorAmount));
        SponsorOffer memory offer1 = sponsorInstance.getOffer(offerId1);
        SponsorOffer memory offer2 = sponsorInstance.getOffer(offerId2);
        SponsorOffer memory offer3 = sponsorInstance.getOffer(offerId3);
        assertTrue(offer1.status == OfferStatus.CANCELED);
        assertTrue(offer2.status == OfferStatus.REFUNDED);
        assertTrue(offer3.status == OfferStatus.CANCELED);
    }
}
