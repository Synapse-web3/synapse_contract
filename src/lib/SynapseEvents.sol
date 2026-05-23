// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Protocol
event EvtProtocolInitialized(address indexed config, address indexed authority);

// Staking
event EvtStaked(address indexed operator, uint256 amount, uint256 newTotal);
event EvtUnstakeRequested(address indexed operator, uint256 amount, uint256 availableAt);
event EvtUnstakeWithdrawn(address indexed operator, uint256 amount);
event EvtOperatorSlashed(address indexed operator, uint256 slashAmount, uint256 remainingStake);

// Hypothesis
event EvtHypothesisCommitted(
    bytes32 indexed hypothesisKey,
    address indexed author,
    uint8   domain,
    uint8   gradeTarget,
    bytes32 saltedHash,
    uint256 blockNumber
);
event EvtHypothesisRevealed(
    bytes32 indexed hypothesisKey,
    address indexed author,
    uint8   domain,
    uint256 revealedAt
);
event EvtHypothesisGraded(bytes32 indexed hypothesisKey, uint8 gradeActual);
event EvtPopsClearanceSet(bytes32 indexed hypothesisKey, bool cleared);

// IP-NFT
event EvtIpnftMinted(
    bytes32 indexed hypothesisKey,
    address indexed nftContract,
    address indexed owner,
    uint8   domain,
    uint8   gradeAtMint,
    uint16  royaltyBps
);

// Lab
event EvtLabRegistered(bytes32 indexed labKey, address indexed operator, string name);
event EvtLabBooked(
    bytes32 indexed bookingKey,
    bytes32 indexed labKey,
    address indexed caller,
    int256  slotStart,
    int256  slotEnd,
    uint256 costUsdc
);
event EvtBookingCancelled(bytes32 indexed bookingKey);
event EvtExperimentResult(bytes32 indexed bookingKey, bytes32 indexed labKey, bytes32 resultHash);

// Campaign
event EvtCampaignCreated(
    bytes32 indexed campaignKey,
    address indexed leadWallet,
    uint256 targetUsdc,
    uint8   domain
);
event EvtCampaignFunded(
    bytes32 indexed campaignKey,
    address indexed funder,
    uint256 amountUsdc,
    uint256 totalRaised
);
event EvtMilestoneVerified(bytes32 indexed campaignKey, uint8 milestoneIndex);
event EvtMilestoneReleased(bytes32 indexed campaignKey, uint8 milestoneIndex, uint256 amountUsdc);

// Treasury
event EvtInferenceRevenueRouted(
    address indexed operator,
    uint256 operatorAmount,
    uint256 treasuryAmount
);
event EvtDataQueryRevenueRouted(
    address indexed contributor,
    uint256 contributorAmount,
    uint256 treasuryAmount
);
