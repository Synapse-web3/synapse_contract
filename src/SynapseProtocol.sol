// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./SynapseIPNFT.sol";
import "./lib/SynapseConstants.sol";
import "./lib/SynapseErrors.sol";
import "./lib/SynapseEvents.sol";
import "./lib/SynapseTypes.sol";

interface IBurnable {
    function burnFrom(address account, uint256 amount) external;
}

contract SynapseProtocol is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ── Config ────────────────────────────────────────────────────────────────
    ProtocolConfig public config;
    bool public initialized;

    // ── Staking ───────────────────────────────────────────────────────────────
    uint256 public totalStaked;
    mapping(address => StakeRecord) public stakeRecords;

    // ── Hypothesis ────────────────────────────────────────────────────────────
    mapping(bytes32 => HypothesisRecord) public hypotheses;

    // ── IP-NFT ────────────────────────────────────────────────────────────────
    SynapseIPNFT public ipNftContract;
    mapping(bytes32 => IpnftRecord) public ipnfts;

    // ── Lab ───────────────────────────────────────────────────────────────────
    mapping(bytes32 => LabRecord)     public labs;
    mapping(bytes32 => BookingRecord) public bookings;

    // ── Campaign ──────────────────────────────────────────────────────────────
    mapping(bytes32 => CampaignRecord) internal _campaigns;
    mapping(bytes32 => uint256)        public campaignEscrow;

    // ── Modifiers ─────────────────────────────────────────────────────────────

    modifier onlyAuthority() {
        if (msg.sender != config.authority) revert Unauthorized();
        _;
    }

    modifier onlyGraderOrAuthority() {
        if (msg.sender != config.evidenceGrader && msg.sender != config.authority)
            revert Unauthorized();
        _;
    }

    modifier onlyBiosecOrAuthority() {
        if (msg.sender != config.biosecurityAgent && msg.sender != config.authority)
            revert Unauthorized();
        _;
    }

    // ── Key helpers ───────────────────────────────────────────────────────────

    function hypothesisKey(address author, bytes8 shortId) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(author, shortId));
    }

    function labKey(address operator, bytes8 _labId) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(operator, _labId));
    }

    function campaignKey(address lead, bytes16 campaignId) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(lead, campaignId));
    }

    function bookingKey(bytes32 _labKey, int256 slotStart) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_labKey, slotStart));
    }

    // ── Struct getters (auto-generated getters unpack to tuples, not struct) ──

    function getHypothesis(bytes32 key) external view returns (HypothesisRecord memory) {
        return hypotheses[key];
    }

    function getIpnft(bytes32 key) external view returns (IpnftRecord memory) {
        return ipnfts[key];
    }

    function getLab(bytes32 key) external view returns (LabRecord memory) {
        return labs[key];
    }

    function getBooking(bytes32 key) external view returns (BookingRecord memory) {
        return bookings[key];
    }

    function getStakeRecord(address who) external view returns (StakeRecord memory) {
        return stakeRecords[who];
    }

    function getCampaign(bytes32 key) external view returns (CampaignRecord memory) {
        return _campaigns[key];
    }

    // ── 8.1 Protocol Initialization ───────────────────────────────────────────

    function setIpNftContract(address _ipNft) external {
        // Allow setting once before initialization is finalized, or by authority post-init
        if (initialized && msg.sender != config.authority) revert Unauthorized();
        ipNftContract = SynapseIPNFT(_ipNft);
    }

    function initializeProtocol(InitializeProtocolParams calldata params) external {
        if (initialized) revert AlreadyInitialized();
        initialized = true;

        config.authority        = msg.sender;
        config.evidenceGrader   = params.evidenceGrader;
        config.biosecurityAgent = params.biosecurityAgent;
        config.treasuryWallet   = params.treasuryWallet;
        config.synapseMint      = params.synapseMint;
        config.usdcMint         = params.usdcMint;
        config.minLabStake      = params.minLabStake;

        emit EvtProtocolInitialized(address(this), msg.sender);
    }

    // ── 8.2 Staking Module ────────────────────────────────────────────────────

    function stakeSynapse(uint256 amount) external nonReentrant {
        if (amount == 0) revert InsufficientSynapse();

        IERC20 synapse = IERC20(config.synapseMint);
        if (synapse.balanceOf(msg.sender) < amount) revert InsufficientSynapse();

        synapse.safeTransferFrom(msg.sender, address(this), amount);

        StakeRecord storage sr = stakeRecords[msg.sender];
        if (sr.operator == address(0)) {
            sr.operator   = msg.sender;
            sr.createdAt  = block.timestamp;
        }
        sr.stakedAmount += amount;
        totalStaked     += amount;

        emit EvtStaked(msg.sender, amount, sr.stakedAmount);
    }

    function requestUnstake(uint256 amount) external {
        StakeRecord storage sr = stakeRecords[msg.sender];
        if (amount == 0 || sr.stakedAmount < amount) revert InsufficientStake();

        sr.lastUnstakeRequest    = block.timestamp;
        sr.unstakeRequestAmount  = amount;

        emit EvtUnstakeRequested(msg.sender, amount, block.timestamp + SynapseConstants.UNSTAKE_COOLDOWN);
    }

    function withdrawUnstake() external nonReentrant {
        StakeRecord storage sr = stakeRecords[msg.sender];
        if (sr.unstakeRequestAmount == 0) revert NoPendingUnstake();
        if (block.timestamp < sr.lastUnstakeRequest + SynapseConstants.UNSTAKE_COOLDOWN)
            revert CooldownNotElapsed();

        uint256 amount = sr.unstakeRequestAmount;
        if (sr.stakedAmount < amount) revert InsufficientStake();

        sr.stakedAmount          -= amount;
        sr.unstakeRequestAmount   = 0;
        sr.lastUnstakeRequest     = 0;
        totalStaked              -= amount;

        IERC20(config.synapseMint).safeTransfer(msg.sender, amount);

        emit EvtUnstakeWithdrawn(msg.sender, amount);
    }

    function slashOperator(address operator, uint256 amount) external onlyAuthority nonReentrant {
        StakeRecord storage sr = stakeRecords[operator];
        uint256 slashAmount = amount > sr.stakedAmount ? sr.stakedAmount : amount;

        sr.stakedAmount  -= slashAmount;
        sr.slashCount    += 1;
        totalStaked      -= slashAmount;

        IERC20(config.synapseMint).safeTransfer(config.treasuryWallet, slashAmount);

        emit EvtOperatorSlashed(operator, slashAmount, sr.stakedAmount);
    }

    // ── 8.3 Hypothesis Registry ───────────────────────────────────────────────

    function commitHypothesis(CommitHypothesisParams calldata params) external nonReentrant {
        bytes32 hypKey = keccak256(abi.encodePacked(msg.sender, params.shortId));
        if (hypotheses[hypKey].author != address(0)) revert Forbidden();

        IERC20 synapse = IERC20(config.synapseMint);
        if (synapse.balanceOf(msg.sender) < SynapseConstants.SYNAPSE_COMMIT_BURN)
            revert InsufficientSynapse();

        IBurnable(config.synapseMint).burnFrom(msg.sender, SynapseConstants.SYNAPSE_COMMIT_BURN);

        hypotheses[hypKey] = HypothesisRecord({
            author:        msg.sender,
            shortId:       params.shortId,
            domain:        params.domain,
            gradeTarget:   params.gradeTarget,
            gradeActual:   GRADE_NONE,
            saltedHash:    params.saltedHash,
            status:        HYP_COMMITTED,
            onChainBlock:  block.number,
            revealedAt:    0,
            popsClearance: POPS_UNSET,
            burnAmount:    SynapseConstants.SYNAPSE_COMMIT_BURN,
            createdAt:     block.timestamp
        });

        emit EvtHypothesisCommitted(
            hypKey,
            msg.sender,
            params.domain,
            params.gradeTarget,
            params.saltedHash,
            block.number
        );
    }

    function revealHypothesis(RevealHypothesisParams calldata params) external {
        bytes32 hypKey = keccak256(abi.encodePacked(msg.sender, params.shortId));
        HypothesisRecord storage h = hypotheses[hypKey];

        if (h.author != msg.sender) revert Forbidden();
        if (h.status != HYP_COMMITTED) revert HypothesisNotCommitted();

        bytes32 computed = keccak256(abi.encodePacked(params.salt, bytes(params.plaintext)));
        if (computed != h.saltedHash) revert HashMismatch();

        h.status     = HYP_REVEALED;
        h.revealedAt = block.timestamp;

        emit EvtHypothesisRevealed(hypKey, msg.sender, h.domain, block.timestamp);
    }

    function setHypothesisGrade(bytes32 hypKey, uint8 grade) external onlyGraderOrAuthority {
        HypothesisRecord storage h = hypotheses[hypKey];
        if (h.status != HYP_REVEALED) revert HypothesisNotRevealed();

        h.gradeActual = grade;
        h.status      = HYP_VERIFIED;

        emit EvtHypothesisGraded(hypKey, grade);
    }

    function setPopsClearance(bytes32 hypKey, bool cleared) external onlyBiosecOrAuthority {
        HypothesisRecord storage h = hypotheses[hypKey];

        // popsClearance is a separate biosecurity signal — it does not overwrite the
        // scientific-review status so that mintIpnft can distinguish PopsShieldFlagged
        // from HypothesisNotVerified with the correct revert reason.
        h.popsClearance = cleared ? POPS_CLEARED : POPS_FLAGGED;

        emit EvtPopsClearanceSet(hypKey, cleared);
    }

    // ── 8.4 IP-NFT Minter ────────────────────────────────────────────────────

    function mintIpnft(bytes32 hypKey, MintIpnftParams calldata params) external nonReentrant {
        HypothesisRecord storage h = hypotheses[hypKey];

        if (h.author != msg.sender) revert Forbidden();
        if (h.status != HYP_VERIFIED) revert HypothesisNotVerified();
        if (h.gradeActual != GRADE_A && h.gradeActual != GRADE_B) revert GradeInsufficient();
        if (h.popsClearance == POPS_UNSET) revert PopsShieldPending();
        if (h.popsClearance == POPS_FLAGGED) revert PopsShieldFlagged();
        if (ipnfts[hypKey].owner != address(0)) revert Forbidden(); // already minted

        IERC20 synapse = IERC20(config.synapseMint);
        if (synapse.balanceOf(msg.sender) < SynapseConstants.SYNAPSE_IPNFT_BURN)
            revert InsufficientSynapse();

        // Hard-burn 25 SYNAPSE
        IBurnable(config.synapseMint).burnFrom(msg.sender, SynapseConstants.IPNFT_BURN_HALF);

        // Transfer 25 SYNAPSE to staking vault (this contract)
        synapse.safeTransferFrom(msg.sender, address(this), SynapseConstants.IPNFT_STAKER_HALF);
        totalStaked += SynapseConstants.IPNFT_STAKER_HALF;

        // Mint ERC-721
        ipNftContract.mint(msg.sender, uint256(hypKey), params.metadataUri, params.royaltyBps);

        ipnfts[hypKey] = IpnftRecord({
            mintAddress: address(ipNftContract),
            hypothesis:  hypKey,
            owner:       msg.sender,
            title:       params.title,
            domain:      h.domain,
            gradeAtMint: h.gradeActual,
            commitHash:  h.saltedHash,
            royaltyBps:  params.royaltyBps,
            metadataUri: params.metadataUri,
            burnAmount:  SynapseConstants.SYNAPSE_IPNFT_BURN,
            createdAt:   block.timestamp
        });

        emit EvtIpnftMinted(
            hypKey,
            address(ipNftContract),
            msg.sender,
            h.domain,
            h.gradeActual,
            params.royaltyBps
        );
    }

    // ── 8.5 Lab Hardware Registry ─────────────────────────────────────────────

    function registerLab(RegisterLabParams calldata params) external {
        StakeRecord storage sr = stakeRecords[msg.sender];
        if (sr.stakedAmount < config.minLabStake) revert InsufficientStake();

        bytes32 lKey = keccak256(abi.encodePacked(msg.sender, params.labId));
        if (labs[lKey].operatorWallet != address(0)) revert Forbidden();

        labs[lKey] = LabRecord({
            name:                  params.name,
            country:               params.country,
            kind:                  params.kind,
            operatorWallet:        msg.sender,
            stakedSynapse:         sr.stakedAmount,
            completedExperiments:  0,
            status:                LAB_IDLE,
            nftMintAddress:        params.nftMintAddress,
            labId:                 params.labId,
            createdAt:             block.timestamp
        });

        emit EvtLabRegistered(lKey, msg.sender, params.name);
    }

    function bookLab(bytes32 lKey, BookLabParams calldata params) external nonReentrant {
        LabRecord storage lab = labs[lKey];
        if (lab.operatorWallet == address(0)) revert Forbidden();
        if (params.slotEnd <= params.slotStart) revert InvalidSlotTimes();

        bytes32 bKey = keccak256(abi.encodePacked(lKey, params.slotStart));
        if (bookings[bKey].callerWallet != address(0)) revert SlotUnavailable();

        IERC20 synapse = IERC20(config.synapseMint);
        if (synapse.balanceOf(msg.sender) < params.feeSynapse) revert InsufficientSynapse();

        // Transfer USDC to lab operator
        IERC20(config.usdcMint).safeTransferFrom(msg.sender, lab.operatorWallet, params.costUsdc);

        // Burn SYNAPSE lab fee
        IBurnable(config.synapseMint).burnFrom(msg.sender, params.feeSynapse);

        bookings[bKey] = BookingRecord({
            labKey:          lKey,
            callerWallet:    msg.sender,
            slotStart:       params.slotStart,
            slotEnd:         params.slotEnd,
            costUsdc:        params.costUsdc,
            feeSynapseBurned: params.feeSynapse,
            status:          BOOKING_CONFIRMED,
            hypothesis:      params.hypothesis,
            resultHash:      bytes32(0),
            createdAt:       block.timestamp
        });

        emit EvtLabBooked(bKey, lKey, msg.sender, params.slotStart, params.slotEnd, params.costUsdc);
    }

    function cancelBooking(bytes32 bKey) external {
        BookingRecord storage b = bookings[bKey];
        if (b.callerWallet != msg.sender) revert Forbidden();
        if (b.status != BOOKING_CONFIRMED) revert BookingNotPending();

        b.status = BOOKING_CANCELLED;

        emit EvtBookingCancelled(bKey);
    }

    function submitExperimentResult(bytes32 bKey, bytes32 resultHash) external {
        BookingRecord storage b = bookings[bKey];
        LabRecord storage lab   = labs[b.labKey];

        if (lab.operatorWallet != msg.sender) revert Forbidden();
        if (b.status != BOOKING_ACTIVE && b.status != BOOKING_CONFIRMED) revert BookingNotPending();

        b.resultHash = resultHash;
        b.status     = BOOKING_COMPLETE;
        lab.completedExperiments += 1;

        emit EvtExperimentResult(bKey, b.labKey, resultHash);
    }

    // ── 8.6 Campaign Escrow ───────────────────────────────────────────────────

    function createCampaign(CreateCampaignParams calldata params) external {
        if (params.milestones.length > SynapseConstants.MAX_MILESTONES) revert TooManyMilestones();

        bytes32 cKey = keccak256(abi.encodePacked(msg.sender, params.id));
        if (_campaigns[cKey].leadWallet != address(0)) revert Forbidden();

        CampaignRecord storage c = _campaigns[cKey];
        c.id          = params.id;
        c.title       = params.title;
        c.domain      = params.domain;
        c.leadWallet  = msg.sender;
        c.targetUsdc  = params.targetUsdc;
        c.raisedUsdc  = 0;
        c.status      = CAMPAIGN_ACTIVE;
        c.createdAt   = block.timestamp;

        for (uint256 i = 0; i < params.milestones.length; i++) {
            c.milestones.push(MilestoneData({
                title:           params.milestones[i].title,
                fundReleaseUsdc: params.milestones[i].fundReleaseUsdc,
                requiredGrade:   params.milestones[i].requiredGrade,
                status:          MILESTONE_PENDING,
                verifiedAt:      0,
                evidenceSig:     ""
            }));
        }

        emit EvtCampaignCreated(cKey, msg.sender, params.targetUsdc, params.domain);
    }

    function fundCampaign(bytes32 cKey, uint256 amountUsdc) external nonReentrant {
        CampaignRecord storage c = _campaigns[cKey];
        if (c.status != CAMPAIGN_ACTIVE) revert CampaignNotActive();

        IERC20(config.usdcMint).safeTransferFrom(msg.sender, address(this), amountUsdc);

        campaignEscrow[cKey] += amountUsdc;
        c.raisedUsdc         += amountUsdc;

        if (c.raisedUsdc >= c.targetUsdc) {
            c.status = CAMPAIGN_FUNDED;
        }

        emit EvtCampaignFunded(cKey, msg.sender, amountUsdc, c.raisedUsdc);
    }

    function verifyMilestone(
        bytes32 cKey,
        uint8   milestoneIndex,
        bytes calldata evidenceSig
    ) external {
        CampaignRecord storage c = _campaigns[cKey];
        if (c.leadWallet != msg.sender) revert Forbidden();
        if (milestoneIndex >= c.milestones.length) revert InvalidMilestoneIndex();

        MilestoneData storage m = c.milestones[milestoneIndex];
        if (m.status != MILESTONE_PENDING) revert MilestoneNotPending();

        m.status      = MILESTONE_VERIFIED;
        m.verifiedAt  = block.timestamp;
        m.evidenceSig = evidenceSig;

        emit EvtMilestoneVerified(cKey, milestoneIndex);
    }

    function releaseMilestoneFunds(bytes32 cKey, uint8 milestoneIndex) external nonReentrant {
        CampaignRecord storage c = _campaigns[cKey];
        if (c.leadWallet != msg.sender && config.authority != msg.sender) revert Forbidden();
        if (milestoneIndex >= c.milestones.length) revert InvalidMilestoneIndex();

        MilestoneData storage m = c.milestones[milestoneIndex];
        if (m.status != MILESTONE_VERIFIED) revert MilestoneNotVerified();

        uint256 amount = m.fundReleaseUsdc;
        require(campaignEscrow[cKey] >= amount, "Escrow insufficient");

        campaignEscrow[cKey] -= amount;
        m.status              = MILESTONE_RELEASED;

        IERC20(config.usdcMint).safeTransfer(c.leadWallet, amount);

        emit EvtMilestoneReleased(cKey, milestoneIndex, amount);
    }

    // ── 8.7 Treasury Revenue Router ───────────────────────────────────────────

    function routeInferenceRevenue(address operator, uint256 totalAmount)
        external
        onlyAuthority
        nonReentrant
    {
        uint256 operatorAmount  = (totalAmount * SynapseConstants.INFERENCE_OPERATOR_BPS)
                                    / SynapseConstants.BPS_DENOMINATOR;
        uint256 treasuryAmount  = totalAmount - operatorAmount;

        IERC20 synapse = IERC20(config.synapseMint);
        synapse.safeTransferFrom(msg.sender, operator, operatorAmount);
        synapse.safeTransferFrom(msg.sender, config.treasuryWallet, treasuryAmount);

        emit EvtInferenceRevenueRouted(operator, operatorAmount, treasuryAmount);
    }

    function routeDataQueryRevenue(address contributor, uint256 totalAmount)
        external
        onlyAuthority
        nonReentrant
    {
        uint256 contributorAmount = (totalAmount * SynapseConstants.DATA_CONTRIBUTOR_BPS)
                                      / SynapseConstants.BPS_DENOMINATOR;
        uint256 treasuryAmount    = totalAmount - contributorAmount;

        IERC20 synapse = IERC20(config.synapseMint);
        synapse.safeTransferFrom(msg.sender, contributor, contributorAmount);
        synapse.safeTransferFrom(msg.sender, config.treasuryWallet, treasuryAmount);

        emit EvtDataQueryRevenueRouted(contributor, contributorAmount, treasuryAmount);
    }
}
