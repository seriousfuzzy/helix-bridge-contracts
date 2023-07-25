// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./LnBridgeHelper.sol";

contract LnDefaultBridgeTarget is LnBridgeHelper {
    uint256 constant public MIN_SLASH_TIMESTAMP = 30 * 60;
    uint256 constant public MAX_TRANSFER_AMOUNT = type(uint112).max;

    struct ProviderInfo {
        uint256 margin;
        uint64 withdrawNonce;
    }

    // providerKey => margin
    // providerKey = hash(provider, sourceToken)
    mapping(bytes32=>ProviderInfo) lnProviderInfos;

    // if slasher == address(0), this FillTransfer is relayed by lnProvider
    // otherwise, this FillTransfer is slashed by slasher
    // if there is no slash transfer before, then it's latestSlashTransferId is assigned by INIT_SLASH_TRANSFER_ID, a special flag
    struct FillTransfer {
        uint64 timestamp;
        address slasher;
    }

    // transferId => FillTransfer
    mapping(bytes32 => FillTransfer) public fillTransfers;

    event TransferFilled(address provider, bytes32 transferId);
    event Slash(bytes32 transferId, address provider, address token, uint256 margin, address slasher);
    event MarginUpdated(address provider, address token, uint112 amount);

    function depositProviderMargin(
        address sourceToken,
        address targetToken,
        uint256 margin
    ) external payable {
        require(margin > 0, "invalid margin");
        bytes32 providerKey = getDefaultProviderKey(msg.sender, sourceToken, targetToken);
        uint256 updatedMargin = lnProviderInfos[providerKey].margin + margin;
        require(updatedMargin < MAX_TRANSFER_AMOUNT, "margin too large");
        lnProviderInfos[providerKey].margin = updatedMargin;
        if (targetToken == address(0)) {
            require(msg.value == margin, "invalid margin value");
        } else {
            _safeTransferFrom(targetToken, msg.sender, address(this), margin);
        }
        emit MarginUpdated(msg.sender, sourceToken, uint112(updatedMargin));
    }

    function transferAndReleaseMargin(
        TransferParameter memory params,
        bytes32 expectedTransferId
    ) external payable {
        require(params.provider == msg.sender, "invalid provider");
        require(params.previousTransferId == bytes32(0) || fillTransfers[params.previousTransferId].timestamp > 0, "last transfer not filled");
        bytes32 transferId = keccak256(abi.encodePacked(
           params.previousTransferId,
           params.provider,
           params.sourceToken,
           params.targetToken,
           params.receiver,
           params.timestamp,
           params.amount));
        require(expectedTransferId == transferId, "check expected transferId failed");
        FillTransfer memory fillTransfer = fillTransfers[transferId];
        // Make sure this transfer was never filled before 
        require(fillTransfer.timestamp == 0, "transfer has been filled");

        fillTransfers[transferId].timestamp = uint64(block.timestamp);

        if (params.targetToken == address(0)) {
            require(msg.value >= params.amount, "lnBridgeTarget:invalid amount");
            payable(params.receiver).transfer(params.amount);
        } else {
            _safeTransferFrom(params.targetToken, msg.sender, params.receiver, uint256(params.amount));
        }
        emit TransferFilled(params.provider, transferId);
    }

    function _withdraw(
        bytes32 lastTransferId,
        uint64 withdrawNonce,
        address provider,
        address sourceToken,
        address targetToken,
        uint112 amount
    ) internal {
        // ensure all transfer has finished
        require(lastTransferId == bytes32(0) || fillTransfers[lastTransferId].timestamp > 0, "last transfer not filled");

        bytes32 providerKey = getDefaultProviderKey(provider, sourceToken, targetToken);
        ProviderInfo memory providerInfo = lnProviderInfos[providerKey];
        // all the early withdraw info ignored
        require(providerInfo.withdrawNonce < withdrawNonce, "withdraw nonce expired");

        // transfer token
        require(providerInfo.margin >= amount, "margin not enough");
        lnProviderInfos[providerKey] = ProviderInfo(providerInfo.margin - amount, withdrawNonce);

        if (targetToken == address(0)) {
            payable(provider).transfer(amount);
        } else {
            _safeTransfer(targetToken, provider, amount);
        }
        emit MarginUpdated(provider, sourceToken, amount);
    }

    function _slash(
        TransferParameter memory params,
        address slasher,
        uint112 fee,
        uint112 penalty
    ) internal {
        require(params.previousTransferId == bytes32(0) || fillTransfers[params.previousTransferId].timestamp > 0, "last transfer not filled");

        bytes32 transferId = keccak256(abi.encodePacked(
            params.previousTransferId,
            params.provider,
            params.sourceToken,
            params.targetToken,
            params.receiver,
            params.timestamp,
            params.amount));
        FillTransfer memory fillTransfer = fillTransfers[transferId];
        require(fillTransfer.slasher == address(0), "transfer has been slashed");
        bytes32 providerKey = getDefaultProviderKey(params.provider, params.sourceToken, params.targetToken);
        ProviderInfo memory providerInfo = lnProviderInfos[providerKey];
        uint256 updatedMargin = providerInfo.margin;
        // transfer is not filled
        if (fillTransfer.timestamp == 0) {
            require(params.timestamp < block.timestamp - MIN_SLASH_TIMESTAMP, "time not expired");
            fillTransfers[transferId] = FillTransfer(uint64(block.timestamp), slasher);

            // 1. transfer token to receiver
            // 2. trnasfer fee and penalty to slasher
            // update margin
            uint256 marginCost = params.amount + fee + penalty;
            require(providerInfo.margin >= marginCost, "margin not enough");
            updatedMargin = providerInfo.margin - marginCost;
            lnProviderInfos[providerKey].margin = updatedMargin;

            if (params.targetToken == address(0)) {
                payable(params.receiver).transfer(params.amount);
                payable(slasher).transfer(fee + penalty);
            } else {
                _safeTransfer(params.targetToken, params.receiver, uint256(params.amount));
                _safeTransfer(params.targetToken, slasher, fee + penalty);
            }
        } else {
            require(fillTransfer.timestamp > params.timestamp + MIN_SLASH_TIMESTAMP, "time not expired");
            // If the transfer fills timeout and no slasher sends the slash message, the margin of this transfer will be locked forever.
            // We utilize this requirement to release the margin.
            // One scenario is when the margin is insufficient due to the execution of slashes after this particular slash transfer.
            // In this case, the slasher cannot cover the gas fee as a penalty.
            // We can acknowledge this situation as it is the slasher's responsibility and the execution should have occurred earlier.
            require(fillTransfer.timestamp > block.timestamp - 2 * MIN_SLASH_TIMESTAMP, "slash a too early transfer");
            fillTransfers[transferId].slasher = slasher;
            // transfer penalty to slasher
            require(providerInfo.margin >= penalty, "margin not enough");
            updatedMargin = providerInfo.margin - penalty;
            lnProviderInfos[providerKey].margin = updatedMargin;
            if (params.targetToken == address(0)) {
                payable(slasher).transfer(penalty);
            } else {
                _safeTransfer(params.targetToken, slasher, penalty);
            }
        }
        emit Slash(transferId, params.provider, params.sourceToken, updatedMargin, slasher);
    }
}

