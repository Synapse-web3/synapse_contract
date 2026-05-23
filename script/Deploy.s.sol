// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/SynapseToken.sol";
import "../src/SynapseIPNFT.sol";
import "../src/SynapseProtocol.sol";
import "../src/lib/SynapseTypes.sol";

contract Deploy is Script {
    // Base USDC
    address constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer    = vm.addr(deployerKey);

        // Optional overrides from env
        address evidenceGrader   = vm.envOr("EVIDENCE_GRADER",   deployer);
        address biosecurityAgent = vm.envOr("BIOSECURITY_AGENT", deployer);
        address treasuryWallet   = vm.envOr("TREASURY_WALLET",   deployer);
        uint256 minLabStake      = vm.envOr("MIN_LAB_STAKE", uint256(100_000_000)); // 100 SYNAPSE

        vm.startBroadcast(deployerKey);

        // 1. Deploy SYNAPSE token
        SynapseToken synapseToken = new SynapseToken(deployer);
        console.log("SynapseToken deployed:", address(synapseToken));

        // 2. Deploy SynapseProtocol
        SynapseProtocol protocol = new SynapseProtocol();
        console.log("SynapseProtocol deployed:", address(protocol));

        // 3. Deploy SynapseIPNFT, linked to protocol
        SynapseIPNFT ipNft = new SynapseIPNFT(address(protocol));
        console.log("SynapseIPNFT deployed:", address(ipNft));

        // 4. Wire NFT contract into protocol
        protocol.setIpNftContract(address(ipNft));

        // 5. Initialize protocol
        protocol.initializeProtocol(InitializeProtocolParams({
            evidenceGrader:   evidenceGrader,
            biosecurityAgent: biosecurityAgent,
            treasuryWallet:   treasuryWallet,
            synapseMint:      address(synapseToken),
            usdcMint:         USDC_BASE,
            minLabStake:      minLabStake
        }));

        // 6. Mint initial supply to deployer (adjust as needed)
        // 1,000,000 SYNAPSE = 1_000_000_000_000 (6 decimals)
        synapseToken.mint(deployer, 1_000_000 * 1e6);
        console.log("Minted 1,000,000 SYNAPSE to deployer");

        vm.stopBroadcast();

        console.log("--- Deployment complete ---");
        console.log("SYNAPSE_TOKEN:    ", address(synapseToken));
        console.log("SYNAPSE_PROTOCOL: ", address(protocol));
        console.log("SYNAPSE_IPNFT:    ", address(ipNft));
        console.log("USDC (Base):       0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913");
    }
}
