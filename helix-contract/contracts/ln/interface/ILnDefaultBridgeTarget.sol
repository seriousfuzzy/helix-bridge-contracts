// SPDX-License-Identifier: MIT

pragma solidity >=0.8.10;
import "../base/LnBridgeHelper.sol";

interface ILnDefaultBridgeTarget {
    function slash(
        LnBridgeHelper.TransferParameter memory params,
        address slasher,
        uint112 fee,
        uint112 penalty
    ) external;

    function withdraw(
        uint256 _sourceChainId,
        bytes32 lastTransferId,
        uint64 withdrawNonce,
        address provider,
        address sourceToken,
        address targetToken,
        uint112 amount
    ) external;
}

