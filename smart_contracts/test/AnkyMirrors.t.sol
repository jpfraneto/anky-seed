// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test} from "forge-std/Test.sol";
import {Continuity} from "../src/ANKY_MIRRORS.sol";

contract AnkyMirrorsTest is Test {
    uint256 private constant MINT_SIGNER_PRIVATE_KEY = 0xA11CE;

    Continuity private mirrors;

    address private owner = makeAddr("owner");
    address private mintSigner = vm.addr(MINT_SIGNER_PRIVATE_KEY);
    address private treasury = makeAddr("treasury");
    address private collector = makeAddr("collector");
    address private secondCollector = makeAddr("secondCollector");
    address private anky;
    uint256 private sponsorFid = 777;

    function setUp() public {
        mirrors = new Continuity(owner, mintSigner, treasury, "ipfs://contract");
        anky = mirrors.ANKY();

        vm.deal(collector, 10 ether);
        vm.deal(secondCollector, 10 ether);
        _mockAnkyBalance(collector, 0);
        _mockAnkyBalance(secondCollector, 0);
    }

    function testConstructorSetsDeploymentState() public view {
        assertEq(mirrors.name(), "Continuity");
        assertEq(mirrors.symbol(), "MIRROR");
        assertEq(mirrors.owner(), owner);
        assertEq(mirrors.mintSigner(), mintSigner);
        assertEq(mirrors.treasury(), treasury);
        assertEq(mirrors.contractURI(), "ipfs://contract");
        assertEq(mirrors.remainingSupply(), mirrors.MAX_SUPPLY());
        assertEq(mirrors.totalReserved(), 0);
        assertTrue(mirrors.mintingEnabled());
    }

    function testClaimMirrorMintsAndRecordsOrigin() public {
        Continuity.MirrorClaim memory claim = _claim(collector, 101, "ipfs://initial", bytes32("reflection"), 1 days);
        bytes memory signature = _signClaim(claim);
        uint256 basePrice = mirrors.BASE_PRICE();

        uint256 startingBalance = collector.balance;

        vm.prank(collector);
        uint256 tokenId = mirrors.claimMirror{value: basePrice + 1 ether}(claim, signature);

        assertEq(tokenId, 1);
        assertEq(mirrors.ownerOf(tokenId), collector);
        assertEq(mirrors.tokenURI(tokenId), "ipfs://initial");
        assertEq(mirrors.totalMinted(), 1);
        assertEq(mirrors.mirrorOfFid(101), tokenId);
        assertEq(mirrors.fidOfMirror(tokenId), 101);
        assertEq(mirrors.claimedMirrorOfWallet(collector), tokenId);
        assertEq(mirrors.reflectionHashOf(tokenId), bytes32("reflection"));
        assertEq(address(mirrors).balance, basePrice);
        assertEq(collector.balance, startingBalance - basePrice);
        assertFalse(mirrors.metadataFrozen(tokenId));
    }

    function testClaimMirrorRejectsReusedFid() public {
        Continuity.MirrorClaim memory firstClaim =
            _claim(collector, 101, "ipfs://initial", bytes32("reflection"), 1 days);
        bytes memory firstSignature = _signClaim(firstClaim);
        uint256 basePrice = mirrors.BASE_PRICE();

        vm.prank(collector);
        mirrors.claimMirror{value: basePrice}(firstClaim, firstSignature);

        Continuity.MirrorClaim memory secondClaim =
            _claim(secondCollector, 101, "ipfs://second", bytes32("second reflection"), 1 days);
        bytes memory secondSignature = _signClaim(secondClaim);

        vm.expectRevert(abi.encodeWithSelector(Continuity.FidAlreadyClaimed.selector, 101));
        vm.prank(secondCollector);
        mirrors.claimMirror{value: basePrice}(secondClaim, secondSignature);
    }

    function testClaimMirrorRejectsReusedWallet() public {
        Continuity.MirrorClaim memory firstClaim =
            _claim(collector, 101, "ipfs://initial", bytes32("reflection"), 1 days);
        bytes memory firstSignature = _signClaim(firstClaim);
        uint256 basePrice = mirrors.BASE_PRICE();

        vm.prank(collector);
        mirrors.claimMirror{value: basePrice}(firstClaim, firstSignature);

        Continuity.MirrorClaim memory secondClaim =
            _claim(collector, 202, "ipfs://second", bytes32("second reflection"), 1 days);
        bytes memory secondSignature = _signClaim(secondClaim);

        vm.expectRevert(abi.encodeWithSelector(Continuity.WalletAlreadyClaimed.selector, collector));
        vm.prank(collector);
        mirrors.claimMirror{value: basePrice}(secondClaim, secondSignature);
    }

    function testClaimMirrorRejectsInvalidSignature() public {
        Continuity.MirrorClaim memory claim = _claim(collector, 101, "ipfs://initial", bytes32("reflection"), 1 days);
        bytes memory signature = _signClaimWithKey(claim, 0xB0B);
        uint256 basePrice = mirrors.BASE_PRICE();

        vm.expectRevert(Continuity.InvalidMirrorSignature.selector);
        vm.prank(collector);
        mirrors.claimMirror{value: basePrice}(claim, signature);
    }

    function testDiscountRequiresMoreThanThresholdAnky() public {
        _mockAnkyBalance(collector, mirrors.ANKY_DISCOUNT_THRESHOLD());
        assertFalse(mirrors.isDiscountEligible(collector));
        assertEq(mirrors.priceFor(collector), mirrors.BASE_PRICE());

        _mockAnkyBalance(collector, mirrors.ANKY_DISCOUNT_THRESHOLD() + 1);
        assertTrue(mirrors.isDiscountEligible(collector));
        assertEq(mirrors.priceFor(collector), mirrors.HOLDER_PRICE());
    }

    function testDiscountedClaimChargesHolderPrice() public {
        _mockAnkyBalance(collector, mirrors.ANKY_DISCOUNT_THRESHOLD() + 1);

        Continuity.MirrorClaim memory claim = _claim(collector, 101, "ipfs://initial", bytes32("reflection"), 1 days);
        bytes memory signature = _signClaim(claim);
        uint256 holderPrice = mirrors.HOLDER_PRICE();

        vm.prank(collector);
        mirrors.claimMirror{value: holderPrice}(claim, signature);

        assertEq(address(mirrors).balance, holderPrice);
    }

    function testGiftMirrorReservesSupplyAndLetsGiftedFidClaimForFree() public {
        Continuity.MirrorGift memory gift = _gift(collector, sponsorFid, 202);
        bytes memory giftSignature = _signGift(gift);
        uint256 basePrice = mirrors.BASE_PRICE();

        vm.prank(collector);
        mirrors.giftMirror{value: basePrice}(gift, giftSignature);

        assertEq(mirrors.totalReserved(), 1);
        assertEq(mirrors.remainingSupply(), mirrors.MAX_SUPPLY() - 1);
        assertTrue(mirrors.giftAvailableForFid(202));
        assertEq(mirrors.sponsorOfFid(202), collector);
        assertEq(mirrors.sponsorFidOfFid(202), sponsorFid);
        assertEq(mirrors.sponsoredPricePaid(202), basePrice);
        assertEq(mirrors.sponsoredFidsByFid(sponsorFid, 0), 202);
        assertEq(mirrors.sponsoredFidsCountByFid(sponsorFid), 1);

        uint256[] memory sponsoredFids = mirrors.getSponsoredFidsByFid(sponsorFid);
        assertEq(sponsoredFids.length, 1);
        assertEq(sponsoredFids[0], 202);

        Continuity.MirrorClaim memory claim =
            _claim(secondCollector, 202, "ipfs://gifted", bytes32("gifted reflection"), 1 days);
        bytes memory claimSignature = _signClaim(claim);

        vm.prank(secondCollector);
        uint256 tokenId = mirrors.claimMirror(claim, claimSignature);

        assertEq(tokenId, 1);
        assertEq(mirrors.ownerOf(tokenId), secondCollector);
        assertEq(address(mirrors).balance, basePrice);
        assertEq(mirrors.totalReserved(), 0);
        assertEq(mirrors.remainingSupply(), mirrors.MAX_SUPPLY() - 1);
        assertFalse(mirrors.giftAvailableForFid(202));
        assertEq(mirrors.sponsorOfFid(202), collector);
        assertEq(mirrors.sponsorFidOfFid(202), sponsorFid);
        assertEq(mirrors.sponsoredPricePaid(202), basePrice);
    }

    function testGiftMirrorUsesSponsorDiscount() public {
        _mockAnkyBalance(collector, mirrors.ANKY_DISCOUNT_THRESHOLD() + 1);

        Continuity.MirrorGift memory gift = _gift(collector, sponsorFid, 202);
        bytes memory giftSignature = _signGift(gift);
        uint256 holderPrice = mirrors.HOLDER_PRICE();

        vm.prank(collector);
        mirrors.giftMirror{value: holderPrice}(gift, giftSignature);

        assertEq(address(mirrors).balance, holderPrice);
        assertEq(mirrors.sponsoredPricePaid(202), holderPrice);
        assertTrue(mirrors.giftAvailableForFid(202));
    }

    function testGiftMirrorRejectsDuplicateGiftedFid() public {
        Continuity.MirrorGift memory firstGift = _gift(collector, sponsorFid, 202);
        bytes memory firstGiftSignature = _signGift(firstGift);
        uint256 basePrice = mirrors.BASE_PRICE();

        vm.prank(collector);
        mirrors.giftMirror{value: basePrice}(firstGift, firstGiftSignature);

        Continuity.MirrorGift memory secondGift = _gift(secondCollector, 888, 202);
        bytes memory secondGiftSignature = _signGift(secondGift);

        vm.expectRevert(abi.encodeWithSelector(Continuity.FidAlreadyGifted.selector, 202));
        vm.prank(secondCollector);
        mirrors.giftMirror{value: basePrice}(secondGift, secondGiftSignature);
    }

    function testGiftMirrorRejectsInvalidSignature() public {
        Continuity.MirrorGift memory gift = _gift(collector, sponsorFid, 202);
        bytes memory giftSignature = _signGiftWithKey(gift, 0xB0B);
        uint256 basePrice = mirrors.BASE_PRICE();

        vm.expectRevert(Continuity.InvalidMirrorGiftSignature.selector);
        vm.prank(collector);
        mirrors.giftMirror{value: basePrice}(gift, giftSignature);
    }

    function testGiftMirrorRejectsMismatchedSponsorWallet() public {
        Continuity.MirrorGift memory gift = _gift(collector, sponsorFid, 202);
        bytes memory giftSignature = _signGift(gift);
        uint256 basePrice = mirrors.BASE_PRICE();

        vm.expectRevert(Continuity.NotGiftSponsor.selector);
        vm.prank(secondCollector);
        mirrors.giftMirror{value: basePrice}(gift, giftSignature);
    }

    function testFinalizeMirrorCanBeCalledByMintSignerOnce() public {
        Continuity.MirrorClaim memory claim = _claim(collector, 101, "ipfs://initial", bytes32("reflection"), 1 days);
        bytes memory signature = _signClaim(claim);
        uint256 basePrice = mirrors.BASE_PRICE();

        vm.prank(collector);
        uint256 tokenId = mirrors.claimMirror{value: basePrice}(claim, signature);

        vm.prank(mintSigner);
        mirrors.finalizeMirror(tokenId, "ipfs://final", bytes32("artifact"));

        assertEq(mirrors.tokenURI(tokenId), "ipfs://final");
        assertEq(mirrors.artifactHashOf(tokenId), bytes32("artifact"));
        assertTrue(mirrors.isMirrorFinalized(tokenId));

        vm.expectRevert(Continuity.MirrorAlreadyFinalized.selector);
        vm.prank(mintSigner);
        mirrors.finalizeMirror(tokenId, "ipfs://another", bytes32("another artifact"));
    }

    function testFinalizeMirrorRejectsUnauthorizedCaller() public {
        Continuity.MirrorClaim memory claim = _claim(collector, 101, "ipfs://initial", bytes32("reflection"), 1 days);
        bytes memory signature = _signClaim(claim);
        uint256 basePrice = mirrors.BASE_PRICE();

        vm.prank(collector);
        uint256 tokenId = mirrors.claimMirror{value: basePrice}(claim, signature);

        vm.expectRevert(Continuity.NotMintSignerOrOwner.selector);
        vm.prank(collector);
        mirrors.finalizeMirror(tokenId, "ipfs://final", bytes32("artifact"));
    }

    function testWithdrawSendsBalanceToTreasury() public {
        Continuity.MirrorClaim memory claim = _claim(collector, 101, "ipfs://initial", bytes32("reflection"), 1 days);
        bytes memory signature = _signClaim(claim);
        uint256 basePrice = mirrors.BASE_PRICE();

        vm.prank(collector);
        mirrors.claimMirror{value: basePrice}(claim, signature);

        uint256 treasuryStartingBalance = treasury.balance;

        vm.prank(owner);
        mirrors.withdraw();

        assertEq(address(mirrors).balance, 0);
        assertEq(treasury.balance, treasuryStartingBalance + basePrice);
    }

    function testOwnerCannotRenounceOwnership() public {
        vm.expectRevert(Continuity.OwnershipCannotBeRenounced.selector);
        vm.prank(owner);
        mirrors.renounceOwnership();
    }

    function _claim(address to, uint256 fid, string memory initialTokenURI, bytes32 reflectionHash, uint256 lifetime)
        private
        view
        returns (Continuity.MirrorClaim memory)
    {
        return Continuity.MirrorClaim({
            to: to,
            fid: fid,
            initialTokenURI: initialTokenURI,
            reflectionHash: reflectionHash,
            deadline: block.timestamp + lifetime
        });
    }

    function _gift(address sponsor, uint256 giftSponsorFid, uint256 giftedFid)
        private
        pure
        returns (Continuity.MirrorGift memory)
    {
        return Continuity.MirrorGift({sponsor: sponsor, sponsorFid: giftSponsorFid, giftedFid: giftedFid});
    }

    function _signClaim(Continuity.MirrorClaim memory claim) private view returns (bytes memory) {
        return _signClaimWithKey(claim, MINT_SIGNER_PRIVATE_KEY);
    }

    function _signGift(Continuity.MirrorGift memory gift) private view returns (bytes memory) {
        return _signGiftWithKey(gift, MINT_SIGNER_PRIVATE_KEY);
    }

    function _signClaimWithKey(Continuity.MirrorClaim memory claim, uint256 privateKey)
        private
        view
        returns (bytes memory)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                mirrors.MIRROR_CLAIM_TYPEHASH(),
                claim.to,
                claim.fid,
                keccak256(bytes(claim.initialTokenURI)),
                claim.reflectionHash,
                claim.deadline
            )
        );

        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("Continuity")),
                keccak256(bytes("1")),
                block.chainid,
                address(mirrors)
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        return abi.encodePacked(r, s, v);
    }

    function _signGiftWithKey(Continuity.MirrorGift memory gift, uint256 privateKey)
        private
        view
        returns (bytes memory)
    {
        bytes32 structHash =
            keccak256(abi.encode(mirrors.MIRROR_GIFT_TYPEHASH(), gift.sponsor, gift.sponsorFid, gift.giftedFid));

        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("Continuity")),
                keccak256(bytes("1")),
                block.chainid,
                address(mirrors)
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        return abi.encodePacked(r, s, v);
    }

    function _mockAnkyBalance(address account, uint256 balance) private {
        vm.mockCall(anky, abi.encodeWithSelector(IERC20.balanceOf.selector, account), abi.encode(balance));
    }
}
