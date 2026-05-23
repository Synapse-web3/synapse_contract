// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SynapseIPNFT is ERC721URIStorage, IERC2981, Ownable {
    address public protocolContract;

    mapping(uint256 => uint16)  private _royaltyBps;
    mapping(uint256 => address) private _royaltyRecipient;

    event IpnftMintedInternal(uint256 indexed tokenId, address indexed to);

    modifier onlyProtocol() {
        require(msg.sender == protocolContract, "Not protocol");
        _;
    }

    constructor(address _protocol) ERC721("Synapse IP-NFT", "SIPNFT") Ownable(_protocol) {
        protocolContract = _protocol;
    }

    function mint(
        address to,
        uint256 tokenId,
        string calldata uri,
        uint16 royaltyBps_
    ) external onlyProtocol {
        _mint(to, tokenId);
        _setTokenURI(tokenId, uri);
        _royaltyBps[tokenId] = royaltyBps_;
        _royaltyRecipient[tokenId] = to;
        emit IpnftMintedInternal(tokenId, to);
    }

    function royaltyInfo(uint256 tokenId, uint256 salePrice)
        external
        view
        override
        returns (address receiver, uint256 royaltyAmount)
    {
        receiver = _royaltyRecipient[tokenId];
        royaltyAmount = (salePrice * _royaltyBps[tokenId]) / 10_000;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721URIStorage, IERC165)
        returns (bool)
    {
        return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }
}
