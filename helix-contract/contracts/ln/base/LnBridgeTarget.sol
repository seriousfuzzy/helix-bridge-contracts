// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "../interface/ILnBridgeSource.sol";
import "./LnBridgeHelper.sol";

contract LnBridgeTarget is LnBridgeHelper {
    uint256 constant public MIN_REFUND_TIMESTAMP = 30 * 60;

    // if slasher == address(0), this FillTransfer is relayed by lnProvider
    // otherwise, this FillTransfer is slashed by slasher
    // if there is no slash transfer before, then it's latestSlashTransferId is assigned by INIT_SLASH_TRANSFER_ID, a special flag
    struct FillTransfer {
        bytes32 latestSlashTransferId;
        address slasher;
    }

    // transferId => FillTransfer
    mapping(bytes32 => FillTransfer) public fillTransfers;

    event TransferFilled(bytes32 transferId, address slasher);

    // if slasher is nonzero, then it's a slash fill transfer
    function _latestSlashFillTransfer(bytes32 previousTransferId) internal view returns(bytes32) {
        FillTransfer memory previous = fillTransfers[previousTransferId];
        // Find the previous refund fill, it is a refund fill if the slasher is not zero address.
        return previous.slasher != address(0) ? previousTransferId : previous.latestSlashTransferId;
    }

    // fill transfer
    // 1. if transfer is not refund or relayed, LnProvider relay message to fill the transfer, and the transfer finished on target chain
    // 2. if transfer is timeout and not processed, slasher(any account) can fill the transfer and request refund
    // if it's filled by slasher, we store the address of the slasher
    // expectedTransferId used to ensure the parameter is the same as on source chain
    function _fillTransfer(
        TransferParameter calldata params,
        bytes32 expectedTransferId,
        address slasher
    ) internal {
        bytes32 transferId = keccak256(abi.encodePacked(
            params.providerKey,
            params.previousTransferId,
            params.lastBlockHash,
            params.nonce,
            params.timestamp,
            params.token,
            params.receiver,
            params.amount));
        require(expectedTransferId == transferId, "check expected transferId failed");
        FillTransfer memory fillTransfer = fillTransfers[transferId];
        // Make sure this transfer was never filled before 
        require(fillTransfer.latestSlashTransferId == bytes32(0), "lnBridgeTarget:message exist");

        // the first fill transfer, we fill the INIT_SLASH_TRANSFER_ID as the latest slash transferId
        if (params.previousTransferId == bytes32(0)) {
            fillTransfers[transferId] = FillTransfer(INIT_SLASH_TRANSFER_ID, slasher);
        } else {
            bytes32 latestSlashTransferId = _latestSlashFillTransfer(params.previousTransferId);
            require(latestSlashTransferId != bytes32(0), "invalid latest slash transfer");
            fillTransfers[transferId] = FillTransfer(latestSlashTransferId, slasher);
        }

        if (params.token == address(0)) {
            require(msg.value >= params.amount, "lnBridgeTarget:invalid amount");
            payable(params.receiver).transfer(params.amount);
        } else {
            _safeTransferFrom(params.token, msg.sender, params.receiver, uint256(params.amount));
        }
        emit TransferFilled(transferId, slasher);
    }

    function transferAndReleaseMargin(
        TransferParameter calldata params,
        bytes32 expectedTransferId
    ) payable external {
        // normal relay message, fill slasher as zero
        _fillTransfer(params, expectedTransferId, address(0));
    }

    // The condition for slash is that the transfer has timed out
    // Meanwhile we need to request a refund transaction to the source chain to withdraw the LnProvider's margin
    // On the source chain, we need to verify all the transfers before has been relayed or slashed.
    // So we needs to carry the the previous shash transferId to ensure that the slash is continuous.
    function _slashAndRemoteRefund(
        TransferParameter calldata params,
        bytes32 expectedTransferId
    ) internal returns(bytes memory message) {
        require(block.timestamp > params.timestamp + MIN_REFUND_TIMESTAMP, "refund time not expired");
        _fillTransfer(params, expectedTransferId, msg.sender);
        // Do not refund `transferId` in source chain unless `latestSlashTransferId` has been refunded
        message = _encodeRefundCall(
            fillTransfers[expectedTransferId].latestSlashTransferId,
            expectedTransferId,
            msg.sender
        );
    }

    // we use this to verify that the transfer has been slashed by user and it can resend the refund request
    function _retrySlashAndRemoteRefund(bytes32 transferId) public view returns(bytes memory message) {
        FillTransfer memory fillTransfer = fillTransfers[transferId];
        require(fillTransfer.slasher != address(0), "invalid refund transfer");
        message = _encodeRefundCall(
            fillTransfer.latestSlashTransferId,
            transferId,
            fillTransfer.slasher
        );
    }

    function _encodeRefundCall(
        bytes32 latestSlashTransferId,
        bytes32 transferId,
        address slasher
    ) internal pure returns(bytes memory) {
        return abi.encodeWithSelector(
            ILnBridgeSource.refund.selector,
            latestSlashTransferId,
            transferId,
            slasher
        );
    }

    function _requestWithdrawMargin(
        bytes32 lastTransferId,
        uint112 amount
    ) internal view returns(bytes memory message) {
        FillTransfer memory fillTransfer = fillTransfers[lastTransferId];
        require(fillTransfer.latestSlashTransferId != bytes32(0), "invalid last transfer");

        return abi.encodeWithSelector(
            ILnBridgeSource.withdrawMargin.selector,
            fillTransfer.latestSlashTransferId,
            lastTransferId,
            msg.sender,
            amount
        );
    }
}

