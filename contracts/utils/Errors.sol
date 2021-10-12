// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./TSUtils.sol";

error GenericError(ErrorCode error);
error UnmatchedPoolState(TSUtils.State state, TSUtils.State requiredState);

enum ErrorCode {
    NO_ERROR,
    MARKET_NOT_LISTED,
    SNAPSHOT_ERROR,
    PRICE_ERROR,
    INSUFFICIENT_LIQUIDITY,
    UNSUFFICIENT_SHORTFALL,
    AUDITOR_MISMATCH,
    TOO_MUCH_REPAY,
    REPAY_ZERO,
    TOKENS_MORE_THAN_BALANCE,
    INVALID_POOL_STATE,
    INVALID_POOL_ID,
    LIQUIDATOR_NOT_BORROWER
}
