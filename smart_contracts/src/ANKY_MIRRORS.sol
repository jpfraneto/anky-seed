// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*
888 Mirrors is not a PFP collection.
It is a public mirror ritual.

One FID may open the mirror once.

Anky reads the public signal:
the casts,
the rhythm,
the repeated tension,
the gift offered so often it becomes visible.

The artifact does not invent a self.
It records continuity.

Not:
who are you?

But:
what keeps showing up through you?

The mirror may move.
The continuity it records does not.

Feeds have watched us silently for years.
This contract marks the opposite gesture:
a pattern seen,
named,
and returned with love.

"The truth will set you free.
But not until it is finished with you."
- David Foster Wallace, Infinite Jest

welcome to the ankyverse
*/

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract Continuity is ERC721URIStorage, Ownable, EIP712, ReentrancyGuard {
    uint256 public constant MAX_SUPPLY = 888;

    uint256 public constant BASE_PRICE = 0.0037 ether;
    uint256 public constant HOLDER_PRICE = BASE_PRICE / 2;

    // $ANKY on Base.
    address public constant ANKY = 0x323e74c31915db296B82b032f9665924f31EFba3;

    // Assumes $ANKY has 18 decimals.
    // Discount applies only if the claiming wallet holds MORE than 8M $ANKY.
    uint256 public constant ANKY_DISCOUNT_THRESHOLD = 8_000_000 ether;

    bytes32 public constant MIRROR_CLAIM_TYPEHASH =
        keccak256("MirrorClaim(address to,uint256 fid,string initialTokenURI,bytes32 reflectionHash,uint256 deadline)");
    bytes32 public constant MIRROR_GIFT_TYPEHASH =
        keccak256("MirrorGift(address sponsor,uint256 sponsorFid,uint256 giftedFid)");

    struct MirrorClaim {
        address to;
        uint256 fid;
        string initialTokenURI;
        bytes32 reflectionHash;
        uint256 deadline;
    }

    struct MirrorGift {
        address sponsor;
        uint256 sponsorFid;
        uint256 giftedFid;
    }

    uint256 public totalMinted;
    uint256 public totalReserved;

    address public mintSigner;
    address public treasury;

    bool public mintingEnabled = true;

    string public contractURI;

    // FID => tokenId
    // This is the sacred invariant:
    // one Farcaster identity may open the mirror once.
    mapping(uint256 => uint256) public mirrorOfFid;

    // tokenId => original FID
    // The NFT may move. Its origin cannot.
    mapping(uint256 => uint256) public fidOfMirror;

    // wallet => tokenId originally claimed by that wallet
    // This does NOT mean current ownership.
    // It only records that this wallet already performed a ritual claim.
    mapping(address => uint256) public claimedMirrorOfWallet;

    // tokenId => hash of the text reflection / claim payload
    // This is set at claim time and never changed.
    mapping(uint256 => bytes32) public reflectionHashOf;

    // tokenId => hash of the final artifact / final metadata payload
    // This is set once during finalization.
    mapping(uint256 => bytes32) public artifactHashOf;

    // false = claimed / mirror forming
    // true = finalized / revealed / sealed
    mapping(uint256 => bool) public metadataFrozen;

    // FID => whether this FID has an unclaimed prepaid mirror.
    mapping(uint256 => bool) public giftAvailableForFid;

    // gifted FID => sponsor wallet
    // Permanent sponsorship ledger.
    mapping(uint256 => address) public sponsorOfFid;

    // gifted FID => sponsor FID
    // Permanent sponsorship ledger.
    mapping(uint256 => uint256) public sponsorFidOfFid;

    // gifted FID => amount paid by sponsor
    // Permanent sponsorship ledger.
    mapping(uint256 => uint256) public sponsoredPricePaid;

    // sponsor FID => all FIDs they have sponsored
    mapping(uint256 => uint256[]) public sponsoredFidsByFid;

    event MirrorClaimed(
        address indexed to,
        uint256 indexed fid,
        uint256 indexed tokenId,
        bytes32 reflectionHash,
        string initialTokenURI,
        bool discounted,
        uint256 pricePaid
    );

    event MirrorGifted(
        address indexed sponsor,
        uint256 indexed sponsorFid,
        uint256 indexed giftedFid,
        bool discounted,
        uint256 pricePaid
    );

    event MirrorFinalized(uint256 indexed tokenId, string finalTokenURI, bytes32 finalArtifactHash);

    event MintSignerUpdated(address indexed oldSigner, address indexed newSigner);

    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);

    event ContractURIUpdated(string newContractURI);
    event MintingEnabledUpdated(bool enabled);

    error MintingClosed();
    error MirrorsComplete();
    error ClaimExpired();
    error NotClaimRecipient();
    error NotGiftSponsor();
    error InvalidFID();
    error EmptyTokenURI();
    error EmptyReflectionHash();
    error EmptyArtifactHash();
    error FidAlreadyClaimed(uint256 fid);
    error FidAlreadyGifted(uint256 fid);
    error WalletAlreadyClaimed(address wallet);
    error InvalidMirrorSignature();
    error InvalidMirrorGiftSignature();
    error InsufficientETH(uint256 required, uint256 sent);
    error RefundFailed();
    error WithdrawFailed();
    error ZeroAddress();
    error NonexistentMirror();
    error MirrorAlreadyFinalized();
    error NotMintSignerOrOwner();
    error OwnershipCannotBeRenounced();

    modifier onlyMintSignerOrOwner() {
        if (msg.sender != mintSigner && msg.sender != owner()) {
            revert NotMintSignerOrOwner();
        }

        _;
    }

    constructor(
        address initialOwner,
        address initialMintSigner,
        address initialTreasury,
        string memory initialContractURI
    ) ERC721("Continuity", "MIRROR") Ownable(initialOwner) EIP712("Continuity", "1") {
        if (initialOwner == address(0)) revert ZeroAddress();
        if (initialMintSigner == address(0)) revert ZeroAddress();
        if (initialTreasury == address(0)) revert ZeroAddress();

        mintSigner = initialMintSigner;
        treasury = initialTreasury;
        contractURI = initialContractURI;
    }

    function claimMirror(MirrorClaim calldata claim, bytes calldata signature)
        external
        payable
        nonReentrant
        returns (uint256 tokenId)
    {
        if (!mintingEnabled) revert MintingClosed();
        if (block.timestamp > claim.deadline) revert ClaimExpired();

        if (claim.to != msg.sender) revert NotClaimRecipient();
        if (claim.fid == 0) revert InvalidFID();
        if (bytes(claim.initialTokenURI).length == 0) revert EmptyTokenURI();
        if (claim.reflectionHash == bytes32(0)) revert EmptyReflectionHash();

        if (mirrorOfFid[claim.fid] != 0) {
            revert FidAlreadyClaimed(claim.fid);
        }

        if (claimedMirrorOfWallet[msg.sender] != 0) {
            revert WalletAlreadyClaimed(msg.sender);
        }

        address recoveredSigner = _recoverSigner(claim, signature);
        if (recoveredSigner != mintSigner) revert InvalidMirrorSignature();

        bool gifted = giftAvailableForFid[claim.fid];
        if (!gifted && totalMinted + totalReserved >= MAX_SUPPLY) revert MirrorsComplete();
        if (gifted) {
            totalReserved -= 1;
            giftAvailableForFid[claim.fid] = false;
        }

        if (totalMinted >= MAX_SUPPLY) revert MirrorsComplete();

        uint256 requiredPrice = gifted ? 0 : priceFor(msg.sender);
        if (msg.value < requiredPrice) {
            revert InsufficientETH(requiredPrice, msg.value);
        }

        tokenId = totalMinted + 1;
        totalMinted = tokenId;

        mirrorOfFid[claim.fid] = tokenId;
        fidOfMirror[tokenId] = claim.fid;
        claimedMirrorOfWallet[msg.sender] = tokenId;
        reflectionHashOf[tokenId] = claim.reflectionHash;

        _safeMint(msg.sender, tokenId);
        _setTokenURI(tokenId, claim.initialTokenURI);

        bool discounted = requiredPrice == HOLDER_PRICE;

        emit MirrorClaimed(
            msg.sender, claim.fid, tokenId, claim.reflectionHash, claim.initialTokenURI, discounted, requiredPrice
        );

        uint256 refund = msg.value - requiredPrice;
        if (refund != 0) {
            (bool ok,) = payable(msg.sender).call{value: refund}("");
            if (!ok) revert RefundFailed();
        }
    }

    function giftMirror(MirrorGift calldata gift, bytes calldata signature) external payable nonReentrant {
        if (!mintingEnabled) revert MintingClosed();
        if (totalMinted + totalReserved >= MAX_SUPPLY) revert MirrorsComplete();

        if (gift.sponsor != msg.sender) revert NotGiftSponsor();
        if (gift.sponsorFid == 0 || gift.giftedFid == 0) revert InvalidFID();

        if (mirrorOfFid[gift.giftedFid] != 0) {
            revert FidAlreadyClaimed(gift.giftedFid);
        }

        if (giftAvailableForFid[gift.giftedFid] || sponsorOfFid[gift.giftedFid] != address(0)) {
            revert FidAlreadyGifted(gift.giftedFid);
        }

        address recoveredSigner = _recoverGiftSigner(gift, signature);
        if (recoveredSigner != mintSigner) revert InvalidMirrorGiftSignature();

        uint256 requiredPrice = priceFor(msg.sender);
        if (msg.value < requiredPrice) {
            revert InsufficientETH(requiredPrice, msg.value);
        }

        totalReserved += 1;
        giftAvailableForFid[gift.giftedFid] = true;
        sponsorOfFid[gift.giftedFid] = msg.sender;
        sponsorFidOfFid[gift.giftedFid] = gift.sponsorFid;
        sponsoredPricePaid[gift.giftedFid] = requiredPrice;
        sponsoredFidsByFid[gift.sponsorFid].push(gift.giftedFid);

        bool discounted = requiredPrice == HOLDER_PRICE;

        emit MirrorGifted(msg.sender, gift.sponsorFid, gift.giftedFid, discounted, requiredPrice);

        uint256 refund = msg.value - requiredPrice;
        if (refund != 0) {
            (bool ok,) = payable(msg.sender).call{value: refund}("");
            if (!ok) revert RefundFailed();
        }
    }

    function finalizeMirror(uint256 tokenId, string calldata finalTokenURI, bytes32 finalArtifactHash)
        external
        onlyMintSignerOrOwner
    {
        if (_ownerOf(tokenId) == address(0)) revert NonexistentMirror();
        if (metadataFrozen[tokenId]) revert MirrorAlreadyFinalized();
        if (bytes(finalTokenURI).length == 0) revert EmptyTokenURI();
        if (finalArtifactHash == bytes32(0)) revert EmptyArtifactHash();

        _setTokenURI(tokenId, finalTokenURI);
        artifactHashOf[tokenId] = finalArtifactHash;
        metadataFrozen[tokenId] = true;

        emit MirrorFinalized(tokenId, finalTokenURI, finalArtifactHash);
    }

    function priceFor(address account) public view returns (uint256) {
        if (isDiscountEligible(account)) {
            return HOLDER_PRICE;
        }

        return BASE_PRICE;
    }

    function isDiscountEligible(address account) public view returns (bool) {
        return IERC20(ANKY).balanceOf(account) > ANKY_DISCOUNT_THRESHOLD;
    }

    function remainingSupply() external view returns (uint256) {
        return MAX_SUPPLY - totalMinted - totalReserved;
    }

    function hasFidClaimed(uint256 fid) external view returns (bool) {
        return mirrorOfFid[fid] != 0;
    }

    function hasWalletClaimed(address wallet) external view returns (bool) {
        return claimedMirrorOfWallet[wallet] != 0;
    }

    function isMirrorFinalized(uint256 tokenId) external view returns (bool) {
        if (_ownerOf(tokenId) == address(0)) revert NonexistentMirror();

        return metadataFrozen[tokenId];
    }

    function getSponsoredFidsByFid(uint256 sponsorFid) external view returns (uint256[] memory) {
        return sponsoredFidsByFid[sponsorFid];
    }

    function sponsoredFidsCountByFid(uint256 sponsorFid) external view returns (uint256) {
        return sponsoredFidsByFid[sponsorFid].length;
    }

    function _recoverSigner(MirrorClaim calldata claim, bytes calldata signature) internal view returns (address) {
        bytes32 structHash = keccak256(
            abi.encode(
                MIRROR_CLAIM_TYPEHASH,
                claim.to,
                claim.fid,
                keccak256(bytes(claim.initialTokenURI)),
                claim.reflectionHash,
                claim.deadline
            )
        );

        bytes32 digest = _hashTypedDataV4(structHash);

        return ECDSA.recover(digest, signature);
    }

    function _recoverGiftSigner(MirrorGift calldata gift, bytes calldata signature) internal view returns (address) {
        bytes32 structHash = keccak256(abi.encode(MIRROR_GIFT_TYPEHASH, gift.sponsor, gift.sponsorFid, gift.giftedFid));

        bytes32 digest = _hashTypedDataV4(structHash);

        return ECDSA.recover(digest, signature);
    }

    function setMintSigner(address newMintSigner) external onlyOwner {
        if (newMintSigner == address(0)) revert ZeroAddress();

        address oldMintSigner = mintSigner;
        mintSigner = newMintSigner;

        emit MintSignerUpdated(oldMintSigner, newMintSigner);
    }

    function setTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert ZeroAddress();

        address oldTreasury = treasury;
        treasury = newTreasury;

        emit TreasuryUpdated(oldTreasury, newTreasury);
    }

    function setContractURI(string calldata newContractURI) external onlyOwner {
        contractURI = newContractURI;

        emit ContractURIUpdated(newContractURI);
    }

    function setMintingEnabled(bool enabled) external onlyOwner {
        mintingEnabled = enabled;

        emit MintingEnabledUpdated(enabled);
    }

    function withdraw() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;

        (bool ok,) = payable(treasury).call{value: balance}("");
        if (!ok) revert WithdrawFailed();
    }

    function renounceOwnership() public pure override {
        revert OwnershipCannotBeRenounced();
    }
}
