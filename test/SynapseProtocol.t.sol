// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/SynapseToken.sol";
import "../src/SynapseIPNFT.sol";
import "../src/SynapseProtocol.sol";
import "../src/lib/SynapseTypes.sol";
import "../src/lib/SynapseConstants.sol";
import "../src/lib/SynapseErrors.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}
    function decimals() public pure override returns (uint8) { return 6; }
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

contract SynapseProtocolTest is Test {
    SynapseToken    internal synapse;
    MockUSDC        internal usdc;
    SynapseIPNFT    internal ipNft;
    SynapseProtocol internal protocol;

    address internal deployer  = address(1);
    address internal grader    = address(2);
    address internal biosec    = address(3);
    address internal treasury  = address(4);
    address internal alice     = address(5);
    address internal bob       = address(6);
    address internal operator  = address(7);

    function setUp() public {
        vm.startPrank(deployer);

        synapse  = new SynapseToken(deployer);
        usdc     = new MockUSDC();
        protocol = new SynapseProtocol();
        ipNft    = new SynapseIPNFT(address(protocol));

        protocol.setIpNftContract(address(ipNft));

        protocol.initializeProtocol(InitializeProtocolParams({
            evidenceGrader:   grader,
            biosecurityAgent: biosec,
            treasuryWallet:   treasury,
            synapseMint:      address(synapse),
            usdcMint:         address(usdc),
            minLabStake:      100_000_000 // 100 SYNAPSE
        }));

        // Fund test accounts
        synapse.mint(alice,    500_000_000); // 500 SYNAPSE
        synapse.mint(bob,      500_000_000);
        synapse.mint(operator, 500_000_000);
        usdc.mint(alice,       1_000_000_000); // 1000 USDC
        usdc.mint(bob,         1_000_000_000);

        vm.stopPrank();
    }

    // ── Staking ───────────────────────────────────────────────────────────────

    function test_StakeSynapse() public {
        vm.startPrank(alice);
        synapse.approve(address(protocol), 200_000_000);
        protocol.stakeSynapse(200_000_000);
        vm.stopPrank();

        StakeRecord memory sr = protocol.getStakeRecord(alice);
        assertEq(sr.stakedAmount, 200_000_000);
        assertEq(protocol.totalStaked(), 200_000_000);
    }

    function test_RequestAndWithdrawUnstake() public {
        vm.startPrank(alice);
        synapse.approve(address(protocol), 200_000_000);
        protocol.stakeSynapse(200_000_000);
        protocol.requestUnstake(100_000_000);
        vm.stopPrank();

        vm.warp(block.timestamp + SynapseConstants.UNSTAKE_COOLDOWN + 1);

        uint256 before = synapse.balanceOf(alice);
        vm.prank(alice);
        protocol.withdrawUnstake();

        assertEq(synapse.balanceOf(alice) - before, 100_000_000);
    }

    function test_CooldownNotElapsed() public {
        vm.startPrank(alice);
        synapse.approve(address(protocol), 200_000_000);
        protocol.stakeSynapse(200_000_000);
        protocol.requestUnstake(100_000_000);
        vm.expectRevert(CooldownNotElapsed.selector);
        protocol.withdrawUnstake();
        vm.stopPrank();
    }

    function test_SlashOperator() public {
        vm.startPrank(alice);
        synapse.approve(address(protocol), 200_000_000);
        protocol.stakeSynapse(200_000_000);
        vm.stopPrank();

        uint256 treasuryBefore = synapse.balanceOf(treasury);
        vm.prank(deployer);
        protocol.slashOperator(alice, 50_000_000);

        assertEq(synapse.balanceOf(treasury) - treasuryBefore, 50_000_000);
        StakeRecord memory sr = protocol.getStakeRecord(alice);
        assertEq(sr.stakedAmount, 150_000_000);
    }

    // ── Hypothesis ────────────────────────────────────────────────────────────

    function test_CommitRevealGrade() public {
        bytes8  shortId   = bytes8(keccak256("id1"));
        bytes   memory salt      = abi.encodePacked(keccak256("salt"));
        string  memory plaintext = "My hypothesis";
        bytes32 saltedHash = keccak256(abi.encodePacked(salt, bytes(plaintext)));

        vm.startPrank(alice);
        synapse.approve(address(protocol), SynapseConstants.SYNAPSE_COMMIT_BURN);
        protocol.commitHypothesis(CommitHypothesisParams({
            shortId:     shortId,
            domain:      1,
            gradeTarget: GRADE_A,
            saltedHash:  saltedHash
        }));
        vm.stopPrank();

        bytes32 hypKey = protocol.hypothesisKey(alice, shortId);
        HypothesisRecord memory h = protocol.getHypothesis(hypKey);
        assertEq(h.status, HYP_COMMITTED);

        vm.prank(alice);
        protocol.revealHypothesis(RevealHypothesisParams({
            shortId:   shortId,
            salt:      salt,
            plaintext: plaintext
        }));

        h = protocol.getHypothesis(hypKey);
        assertEq(h.status, HYP_REVEALED);

        vm.prank(grader);
        protocol.setHypothesisGrade(hypKey, GRADE_A);

        h = protocol.getHypothesis(hypKey);
        assertEq(h.status, HYP_VERIFIED);
        assertEq(h.gradeActual, GRADE_A);
    }

    function test_HashMismatch() public {
        bytes8  shortId    = bytes8(keccak256("id2"));
        bytes32 saltedHash = keccak256("wrong");

        vm.startPrank(alice);
        synapse.approve(address(protocol), SynapseConstants.SYNAPSE_COMMIT_BURN);
        protocol.commitHypothesis(CommitHypothesisParams({
            shortId:     shortId,
            domain:      0,
            gradeTarget: GRADE_B,
            saltedHash:  saltedHash
        }));

        vm.expectRevert(HashMismatch.selector);
        protocol.revealHypothesis(RevealHypothesisParams({
            shortId:   shortId,
            salt:      "badsalt",
            plaintext: "text"
        }));
        vm.stopPrank();
    }

    // ── IP-NFT ────────────────────────────────────────────────────────────────

    function _setupVerifiedHypothesis(address user, bytes8 shortId) internal returns (bytes32 hypKey) {
        bytes   memory salt      = abi.encodePacked(keccak256("saltnft"));
        string  memory plaintext = "Grade A hypothesis";
        bytes32 saltedHash = keccak256(abi.encodePacked(salt, bytes(plaintext)));

        vm.startPrank(user);
        synapse.approve(address(protocol), SynapseConstants.SYNAPSE_COMMIT_BURN);
        protocol.commitHypothesis(CommitHypothesisParams({
            shortId:     shortId,
            domain:      0,
            gradeTarget: GRADE_A,
            saltedHash:  saltedHash
        }));
        protocol.revealHypothesis(RevealHypothesisParams({
            shortId:   shortId,
            salt:      salt,
            plaintext: plaintext
        }));
        vm.stopPrank();

        hypKey = protocol.hypothesisKey(user, shortId);

        vm.prank(grader);
        protocol.setHypothesisGrade(hypKey, GRADE_A);

        vm.prank(biosec);
        protocol.setPopsClearance(hypKey, true);
    }

    function test_MintIpnft() public {
        bytes8 shortId = bytes8(keccak256("nft1"));
        bytes32 hypKey = _setupVerifiedHypothesis(alice, shortId);

        vm.startPrank(alice);
        synapse.approve(address(protocol), SynapseConstants.SYNAPSE_IPNFT_BURN);
        protocol.mintIpnft(hypKey, MintIpnftParams({
            title:       "CRISPR-based BRCA1 repair",
            royaltyBps:  420,
            metadataUri: "ipfs://bafybeig"
        }));
        vm.stopPrank();

        assertEq(ipNft.ownerOf(uint256(hypKey)), alice);

        IpnftRecord memory rec = protocol.getIpnft(hypKey);
        assertEq(rec.owner, alice);
        assertEq(rec.gradeAtMint, GRADE_A);
    }

    function test_MintIpnftGradeInsufficient() public {
        bytes8 shortId  = bytes8(keccak256("nft2"));
        bytes  memory salt      = abi.encodePacked(keccak256("s2"));
        string memory plaintext = "C grade";
        bytes32 saltedHash = keccak256(abi.encodePacked(salt, bytes(plaintext)));

        vm.startPrank(alice);
        synapse.approve(address(protocol), SynapseConstants.SYNAPSE_COMMIT_BURN);
        protocol.commitHypothesis(CommitHypothesisParams({
            shortId:     shortId,
            domain:      0,
            gradeTarget: GRADE_C,
            saltedHash:  saltedHash
        }));
        protocol.revealHypothesis(RevealHypothesisParams({
            shortId:   shortId,
            salt:      salt,
            plaintext: plaintext
        }));
        vm.stopPrank();

        bytes32 hypKey = protocol.hypothesisKey(alice, shortId);
        vm.prank(grader);
        protocol.setHypothesisGrade(hypKey, GRADE_C);

        vm.prank(biosec);
        protocol.setPopsClearance(hypKey, true);

        vm.startPrank(alice);
        synapse.approve(address(protocol), SynapseConstants.SYNAPSE_IPNFT_BURN);
        vm.expectRevert(GradeInsufficient.selector);
        protocol.mintIpnft(hypKey, MintIpnftParams({
            title:       "bad",
            royaltyBps:  100,
            metadataUri: "ipfs://x"
        }));
        vm.stopPrank();
    }

    // ── Lab ───────────────────────────────────────────────────────────────────

    function test_RegisterAndBookLab() public {
        // Operator stakes
        vm.startPrank(operator);
        synapse.approve(address(protocol), 200_000_000);
        protocol.stakeSynapse(200_000_000);

        protocol.registerLab(RegisterLabParams({
            labId:          bytes8(keccak256("lab1")),
            name:           "Alpha Lab",
            country:        bytes4(0x44455500), // "DEU\0"
            kind:           1,
            nftMintAddress: address(0)
        }));
        vm.stopPrank();

        bytes32 lKey = protocol.labKey(operator, bytes8(keccak256("lab1")));
        LabRecord memory lab = protocol.getLab(lKey);
        assertEq(lab.name, "Alpha Lab");

        // Alice books the lab
        vm.startPrank(alice);
        synapse.approve(address(protocol), 500_000);
        usdc.approve(address(protocol), 10_000_000);
        protocol.bookLab(lKey, BookLabParams({
            slotStart: 1_700_000_000,
            slotEnd:   1_700_003_600,
            costUsdc:  10_000_000,
            feeSynapse: 500_000,
            hypothesis: bytes32(0)
        }));
        vm.stopPrank();

        bytes32 bKey = protocol.bookingKey(lKey, 1_700_000_000);
        BookingRecord memory bk = protocol.getBooking(bKey);
        assertEq(bk.status, BOOKING_CONFIRMED);
        assertEq(bk.callerWallet, alice);
    }

    // ── Campaign ──────────────────────────────────────────────────────────────

    function test_CampaignLifecycle() public {
        bytes16 id = bytes16(keccak256("camp1"));

        MilestoneInit[] memory mils = new MilestoneInit[](2);
        mils[0] = MilestoneInit({ title: "Setup",   fundReleaseUsdc: 200_000_000, requiredGrade: GRADE_NONE });
        mils[1] = MilestoneInit({ title: "Trial",   fundReleaseUsdc: 300_000_000, requiredGrade: GRADE_A });

        vm.prank(alice);
        protocol.createCampaign(CreateCampaignParams({
            id:         id,
            title:      "Gene Therapy",
            domain:     0,
            targetUsdc: 500_000_000,
            milestones: mils
        }));

        bytes32 cKey = protocol.campaignKey(alice, id);
        CampaignRecord memory c = protocol.getCampaign(cKey);
        assertEq(c.status, CAMPAIGN_ACTIVE);

        // Fund
        vm.startPrank(bob);
        usdc.approve(address(protocol), 500_000_000);
        protocol.fundCampaign(cKey, 500_000_000);
        vm.stopPrank();

        c = protocol.getCampaign(cKey);
        assertEq(c.status, CAMPAIGN_FUNDED);
        assertEq(protocol.campaignEscrow(cKey), 500_000_000);

        // Verify milestone 0
        vm.prank(alice);
        protocol.verifyMilestone(cKey, 0, "0xdeadbeef");

        // Release milestone 0
        uint256 before = usdc.balanceOf(alice);
        vm.prank(alice);
        protocol.releaseMilestoneFunds(cKey, 0);
        assertEq(usdc.balanceOf(alice) - before, 200_000_000);
    }

    // ── Treasury ──────────────────────────────────────────────────────────────

    function test_RouteInferenceRevenue() public {
        vm.startPrank(deployer);
        synapse.mint(deployer, 1_000_000_000);
        synapse.approve(address(protocol), 1_000_000_000);

        uint256 opBefore  = synapse.balanceOf(bob);
        uint256 trsBefore = synapse.balanceOf(treasury);

        protocol.routeInferenceRevenue(bob, 100_000_000);
        vm.stopPrank();

        assertEq(synapse.balanceOf(bob) - opBefore,     70_000_000);
        assertEq(synapse.balanceOf(treasury) - trsBefore, 30_000_000);
    }

    function test_RouteDataQueryRevenue() public {
        vm.startPrank(deployer);
        synapse.mint(deployer, 1_000_000_000);
        synapse.approve(address(protocol), 1_000_000_000);

        uint256 contribBefore = synapse.balanceOf(alice);
        uint256 trsBefore     = synapse.balanceOf(treasury);

        protocol.routeDataQueryRevenue(alice, 100_000_000);
        vm.stopPrank();

        assertEq(synapse.balanceOf(alice) - contribBefore,  80_000_000);
        assertEq(synapse.balanceOf(treasury) - trsBefore,   20_000_000);
    }

    // ── Staking edge cases ────────────────────────────────────────────────────

    function test_NoPendingUnstake() public {
        vm.startPrank(alice);
        synapse.approve(address(protocol), 100_000_000);
        protocol.stakeSynapse(100_000_000);
        vm.expectRevert(NoPendingUnstake.selector);
        protocol.withdrawUnstake();
        vm.stopPrank();
    }

    function test_AlreadyInitialized() public {
        vm.prank(deployer);
        vm.expectRevert(AlreadyInitialized.selector);
        protocol.initializeProtocol(InitializeProtocolParams({
            evidenceGrader:   grader,
            biosecurityAgent: biosec,
            treasuryWallet:   treasury,
            synapseMint:      address(synapse),
            usdcMint:         address(usdc),
            minLabStake:      100_000_000
        }));
    }

    // ── Booking edge cases ────────────────────────────────────────────────────

    function test_CancelBooking() public {
        // Set up operator + lab
        vm.startPrank(operator);
        synapse.approve(address(protocol), 200_000_000);
        protocol.stakeSynapse(200_000_000);
        protocol.registerLab(RegisterLabParams({
            labId:          bytes8(keccak256("lab2")),
            name:           "Beta Lab",
            country:        bytes4(0x44455500),
            kind:           0,
            nftMintAddress: address(0)
        }));
        vm.stopPrank();

        bytes32 lKey = protocol.labKey(operator, bytes8(keccak256("lab2")));

        // Alice books
        vm.startPrank(alice);
        synapse.approve(address(protocol), 500_000);
        usdc.approve(address(protocol), 5_000_000);
        protocol.bookLab(lKey, BookLabParams({
            slotStart:  1_800_000_000,
            slotEnd:    1_800_003_600,
            costUsdc:   5_000_000,
            feeSynapse: 500_000,
            hypothesis: bytes32(0)
        }));
        vm.stopPrank();

        bytes32 bKey = protocol.bookingKey(lKey, 1_800_000_000);
        assertEq(protocol.getBooking(bKey).status, BOOKING_CONFIRMED);

        vm.prank(alice);
        protocol.cancelBooking(bKey);

        assertEq(protocol.getBooking(bKey).status, BOOKING_CANCELLED);
    }

    function test_DoubleBookingReverts() public {
        vm.startPrank(operator);
        synapse.approve(address(protocol), 200_000_000);
        protocol.stakeSynapse(200_000_000);
        protocol.registerLab(RegisterLabParams({
            labId:          bytes8(keccak256("lab3")),
            name:           "Gamma Lab",
            country:        bytes4(0x44455500),
            kind:           2,
            nftMintAddress: address(0)
        }));
        vm.stopPrank();

        bytes32 lKey = protocol.labKey(operator, bytes8(keccak256("lab3")));

        // First booking — should succeed
        vm.startPrank(alice);
        synapse.approve(address(protocol), 1_000_000);
        usdc.approve(address(protocol), 20_000_000);
        protocol.bookLab(lKey, BookLabParams({
            slotStart:  1_900_000_000,
            slotEnd:    1_900_003_600,
            costUsdc:   10_000_000,
            feeSynapse: 500_000,
            hypothesis: bytes32(0)
        }));
        vm.stopPrank();

        // Second booking at same slot — should revert
        vm.startPrank(bob);
        synapse.approve(address(protocol), 500_000);
        usdc.approve(address(protocol), 10_000_000);
        vm.expectRevert(SlotUnavailable.selector);
        protocol.bookLab(lKey, BookLabParams({
            slotStart:  1_900_000_000,
            slotEnd:    1_900_003_600,
            costUsdc:   10_000_000,
            feeSynapse: 500_000,
            hypothesis: bytes32(0)
        }));
        vm.stopPrank();
    }

    function test_SubmitExperimentResult() public {
        vm.startPrank(operator);
        synapse.approve(address(protocol), 200_000_000);
        protocol.stakeSynapse(200_000_000);
        protocol.registerLab(RegisterLabParams({
            labId:          bytes8(keccak256("lab4")),
            name:           "Delta Lab",
            country:        bytes4(0x44455500),
            kind:           1,
            nftMintAddress: address(0)
        }));
        vm.stopPrank();

        bytes32 lKey = protocol.labKey(operator, bytes8(keccak256("lab4")));

        vm.startPrank(alice);
        synapse.approve(address(protocol), 500_000);
        usdc.approve(address(protocol), 10_000_000);
        protocol.bookLab(lKey, BookLabParams({
            slotStart:  2_000_000_000,
            slotEnd:    2_000_003_600,
            costUsdc:   10_000_000,
            feeSynapse: 500_000,
            hypothesis: bytes32(0)
        }));
        vm.stopPrank();

        bytes32 bKey = protocol.bookingKey(lKey, 2_000_000_000);
        bytes32 resultHash = keccak256("experiment result data");

        vm.prank(operator);
        protocol.submitExperimentResult(bKey, resultHash);

        BookingRecord memory bk = protocol.getBooking(bKey);
        assertEq(bk.status, BOOKING_COMPLETE);
        assertEq(bk.resultHash, resultHash);
        assertEq(protocol.getLab(lKey).completedExperiments, 1);
    }

    // ── Hypothesis PoPS flagging blocks IP-NFT mint ───────────────────────────

    function test_PopsShieldFlaggedBlocksMint() public {
        bytes8  shortId    = bytes8(keccak256("flagged1"));
        bytes   memory salt      = abi.encodePacked(keccak256("sf1"));
        string  memory plaintext = "Dual-use hypothesis";
        bytes32 saltedHash = keccak256(abi.encodePacked(salt, bytes(plaintext)));

        vm.startPrank(alice);
        synapse.approve(address(protocol), SynapseConstants.SYNAPSE_COMMIT_BURN);
        protocol.commitHypothesis(CommitHypothesisParams({
            shortId:     shortId,
            domain:      2,
            gradeTarget: GRADE_A,
            saltedHash:  saltedHash
        }));
        protocol.revealHypothesis(RevealHypothesisParams({
            shortId:   shortId,
            salt:      salt,
            plaintext: plaintext
        }));
        vm.stopPrank();

        bytes32 hypKey = protocol.hypothesisKey(alice, shortId);

        vm.prank(grader);
        protocol.setHypothesisGrade(hypKey, GRADE_A);

        // Biosecurity flags it
        vm.prank(biosec);
        protocol.setPopsClearance(hypKey, false);

        HypothesisRecord memory h = protocol.getHypothesis(hypKey);
        assertEq(h.popsClearance, POPS_FLAGGED);
        assertEq(h.status, HYP_VERIFIED); // status unchanged; popsClearance carries the biosec signal

        // Mint should revert with PopsShieldFlagged
        vm.startPrank(alice);
        synapse.approve(address(protocol), SynapseConstants.SYNAPSE_IPNFT_BURN);
        vm.expectRevert(PopsShieldFlagged.selector);
        protocol.mintIpnft(hypKey, MintIpnftParams({
            title:       "flagged",
            royaltyBps:  100,
            metadataUri: "ipfs://x"
        }));
        vm.stopPrank();
    }

    function test_PopsShieldPendingBlocksMint() public {
        bytes8 shortId = bytes8(keccak256("pending1"));
        bytes  memory salt      = abi.encodePacked(keccak256("sp1"));
        string memory plaintext = "Pending clearance hypothesis";
        bytes32 saltedHash = keccak256(abi.encodePacked(salt, bytes(plaintext)));

        vm.startPrank(alice);
        synapse.approve(address(protocol), SynapseConstants.SYNAPSE_COMMIT_BURN);
        protocol.commitHypothesis(CommitHypothesisParams({
            shortId:     shortId,
            domain:      0,
            gradeTarget: GRADE_A,
            saltedHash:  saltedHash
        }));
        protocol.revealHypothesis(RevealHypothesisParams({
            shortId:   shortId,
            salt:      salt,
            plaintext: plaintext
        }));
        vm.stopPrank();

        bytes32 hypKey = protocol.hypothesisKey(alice, shortId);
        vm.prank(grader);
        protocol.setHypothesisGrade(hypKey, GRADE_A);
        // PoPS clearance NOT set — POPS_UNSET

        vm.startPrank(alice);
        synapse.approve(address(protocol), SynapseConstants.SYNAPSE_IPNFT_BURN);
        vm.expectRevert(PopsShieldPending.selector);
        protocol.mintIpnft(hypKey, MintIpnftParams({
            title:       "pending",
            royaltyBps:  100,
            metadataUri: "ipfs://y"
        }));
        vm.stopPrank();
    }

    // ── Campaign: authority can release milestone funds ────────────────────────

    function test_AuthorityReleaseMilestone() public {
        bytes16 id = bytes16(keccak256("camp2"));

        MilestoneInit[] memory mils = new MilestoneInit[](1);
        mils[0] = MilestoneInit({ title: "Phase 1", fundReleaseUsdc: 100_000_000, requiredGrade: GRADE_NONE });

        vm.prank(alice);
        protocol.createCampaign(CreateCampaignParams({
            id:         id,
            title:      "Authority Release Test",
            domain:     1,
            targetUsdc: 100_000_000,
            milestones: mils
        }));

        bytes32 cKey = protocol.campaignKey(alice, id);

        vm.startPrank(bob);
        usdc.approve(address(protocol), 100_000_000);
        protocol.fundCampaign(cKey, 100_000_000);
        vm.stopPrank();

        vm.prank(alice);
        protocol.verifyMilestone(cKey, 0, "0xsig");

        // Authority (deployer) releases — not the lead
        uint256 before = usdc.balanceOf(alice);
        vm.prank(deployer);
        protocol.releaseMilestoneFunds(cKey, 0);

        assertEq(usdc.balanceOf(alice) - before, 100_000_000);
    }
}

