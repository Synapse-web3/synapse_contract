// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ── Grade constants ────────────────────────────────────────────────────────────
uint8 constant GRADE_A    = 0;
uint8 constant GRADE_B    = 1;
uint8 constant GRADE_C    = 2;
uint8 constant GRADE_D    = 3;
uint8 constant GRADE_X    = 4;
uint8 constant GRADE_NONE = 0xFF;

// ── HypothesisRecord.status ────────────────────────────────────────────────────
uint8 constant HYP_COMMITTED      = 0;
uint8 constant HYP_PENDING_REVEAL = 1;
uint8 constant HYP_REVEALED       = 2;
uint8 constant HYP_VERIFIED       = 3;
uint8 constant HYP_FLAGGED        = 4;
uint8 constant HYP_REJECTED       = 5;

// ── HypothesisRecord.popsClearance ─────────────────────────────────────────────
uint8 constant POPS_UNSET   = 0;
uint8 constant POPS_CLEARED = 1;
uint8 constant POPS_FLAGGED = 2;

// ── CampaignRecord.status ──────────────────────────────────────────────────────
uint8 constant CAMPAIGN_ACTIVE    = 0;
uint8 constant CAMPAIGN_FUNDED    = 1;
uint8 constant CAMPAIGN_COMPLETE  = 2;
uint8 constant CAMPAIGN_CANCELLED = 3;

// ── MilestoneData.status ───────────────────────────────────────────────────────
uint8 constant MILESTONE_PENDING  = 0;
uint8 constant MILESTONE_VERIFIED = 1;
uint8 constant MILESTONE_RELEASED = 2;

// ── LabRecord.status ───────────────────────────────────────────────────────────
uint8 constant LAB_IDLE        = 0;
uint8 constant LAB_BUSY        = 1;
uint8 constant LAB_MAINTENANCE = 2;

// ── BookingRecord.status ───────────────────────────────────────────────────────
uint8 constant BOOKING_PENDING   = 0;
uint8 constant BOOKING_CONFIRMED = 1;
uint8 constant BOOKING_ACTIVE    = 2;
uint8 constant BOOKING_COMPLETE  = 3;
uint8 constant BOOKING_CANCELLED = 4;

// ── Structs ────────────────────────────────────────────────────────────────────

struct ProtocolConfig {
    address authority;
    address evidenceGrader;
    address biosecurityAgent;
    address treasuryWallet;
    address synapseMint;
    address usdcMint;
    uint256 minLabStake;
}

struct HypothesisRecord {
    address author;
    bytes8  shortId;
    uint8   domain;
    uint8   gradeTarget;
    uint8   gradeActual;
    bytes32 saltedHash;
    uint8   status;
    uint256 onChainBlock;
    uint256 revealedAt;
    uint8   popsClearance;
    uint256 burnAmount;
    uint256 createdAt;
}

struct IpnftRecord {
    address mintAddress;
    bytes32 hypothesis;
    address owner;
    string  title;
    uint8   domain;
    uint8   gradeAtMint;
    bytes32 commitHash;
    uint16  royaltyBps;
    string  metadataUri;
    uint256 burnAmount;
    uint256 createdAt;
}

struct MilestoneData {
    string  title;
    uint256 fundReleaseUsdc;
    uint8   requiredGrade;
    uint8   status;
    uint256 verifiedAt;
    bytes   evidenceSig;
}

struct CampaignRecord {
    bytes16          id;
    string           title;
    uint8            domain;
    address          leadWallet;
    uint256          targetUsdc;
    uint256          raisedUsdc;
    uint8            status;
    MilestoneData[]  milestones;
    uint256          createdAt;
}

struct LabRecord {
    string  name;
    bytes4  country;
    uint8   kind;
    address operatorWallet;
    uint256 stakedSynapse;
    uint256 completedExperiments;
    uint8   status;
    address nftMintAddress;
    bytes8  labId;
    uint256 createdAt;
}

struct BookingRecord {
    bytes32 labKey;
    address callerWallet;
    int256  slotStart;
    int256  slotEnd;
    uint256 costUsdc;
    uint256 feeSynapseBurned;
    uint8   status;
    bytes32 hypothesis;
    bytes32 resultHash;
    uint256 createdAt;
}

struct StakeRecord {
    address operator;
    uint256 stakedAmount;
    uint256 lastUnstakeRequest;
    uint256 unstakeRequestAmount;
    uint256 slashCount;
    uint256 createdAt;
}

// ── Calldata parameter structs ─────────────────────────────────────────────────

struct InitializeProtocolParams {
    address evidenceGrader;
    address biosecurityAgent;
    address treasuryWallet;
    address synapseMint;
    address usdcMint;
    uint256 minLabStake;
}

struct CommitHypothesisParams {
    bytes8  shortId;
    uint8   domain;
    uint8   gradeTarget;
    bytes32 saltedHash;
}

struct RevealHypothesisParams {
    bytes8 shortId;
    bytes  salt;
    string plaintext;
}

struct MintIpnftParams {
    string title;
    uint16 royaltyBps;
    string metadataUri;
}

struct RegisterLabParams {
    bytes8  labId;
    string  name;
    bytes4  country;
    uint8   kind;
    address nftMintAddress;
}

struct BookLabParams {
    int256  slotStart;
    int256  slotEnd;
    uint256 costUsdc;
    uint256 feeSynapse;
    bytes32 hypothesis;
}

struct MilestoneInit {
    string  title;
    uint256 fundReleaseUsdc;
    uint8   requiredGrade;
}

struct CreateCampaignParams {
    bytes16         id;
    string          title;
    uint8           domain;
    uint256         targetUsdc;
    MilestoneInit[] milestones;
}
