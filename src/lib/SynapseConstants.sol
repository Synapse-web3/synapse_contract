// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library SynapseConstants {
    // SYNAPSE token has 6 decimals
    uint256 constant SYNAPSE_COMMIT_BURN = 10_000_000;  // 10 SYNAPSE
    uint256 constant SYNAPSE_IPNFT_BURN  = 50_000_000;  // 50 SYNAPSE
    uint256 constant IPNFT_BURN_HALF     = 25_000_000;  // 25 SYNAPSE hard-burned
    uint256 constant IPNFT_STAKER_HALF   = 25_000_000;  // 25 SYNAPSE to staker vault

    uint256 constant DATA_QUERY_COST     = 100_000;     // 0.1 SYNAPSE

    uint256 constant LAB_FEE_BPS         = 500;         // 5%
    uint256 constant BPS_DENOMINATOR     = 10_000;

    // Revenue splits (basis points)
    uint256 constant INFERENCE_OPERATOR_BPS = 7_000;    // 70%
    uint256 constant INFERENCE_TREASURY_BPS = 3_000;    // 30%
    uint256 constant DATA_CONTRIBUTOR_BPS   = 8_000;    // 80%
    uint256 constant DATA_TREASURY_BPS      = 2_000;    // 20%

    // Unstake cooldown: 7 days in seconds
    uint256 constant UNSTAKE_COOLDOWN    = 7 * 24 * 60 * 60;

    // Collection / string limits
    uint256 constant MAX_MILESTONES      = 10;
    uint256 constant MAX_TITLE_LEN       = 128;
    uint256 constant MAX_MILESTONE_TITLE = 64;
    uint256 constant MAX_URI_LEN         = 200;
    uint256 constant MAX_LAB_NAME        = 64;
}
