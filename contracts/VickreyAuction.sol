// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import "@fhenixprotocol/contracts/FHE.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import { Vault } from "./Vault.sol";

struct Auction {
    uint40 startTime;
    address proposer; // == owner of NFT
    uint40 duration;
    address targetAddress;
    uint256 tokenId;
    uint256 reservePrice;
    address paymentAddress; // shield ERC-20 token address
}

struct Bids {
    euint128 bid1; // highest bid
    euint128 bid2; // second highest bid
}

// nonce system like PWN protocol for bidders?

contract VickreyAuction is Vault {
    // To do:
    // - slot optimisation, grouping mappings into structs where data is used together commonly
    // - @question use a counter or the auction hash?
    // - @question do we even need euint256? can it be euint128? Needs to be euin128 to us some FHS.sol operations.
    // - @question add events with the auction hash for indexing?

    // params auction hash => is auction made
    mapping(bytes32 => bool) public auctionsMade;

    // params auction hash => highest bid
    mapping(bytes32 => Bids) public bids;

    // bidder address => bid value (should be euint256)
    mapping(address => euint128) public bidsPerAddr;

    // params auction hash => highest bidder/beneficiary
    mapping(bytes32 => address) internal beneficiary;

    // params auction hash => nft claimed
    mapping(bytes32 => bool) internal claimed;

    // params auction hash => tokens withdrawn by proposer
    mapping(bytes32 => bool) internal withdrawn;

    uint256 internal constant MAXIMUM_DURATION = 7 days;

    /*----------------------------------------------------------*|
    |*  # ERRORS DEFINITIONS                                    *|
    |*----------------------------------------------------------*/

    error CallerIsNotStatedProposer(address proposer);

    error InvalidAuctionStartTime(uint40 time);

    error InvalidAuctionDuration(uint40 duration);

    error InvalidPaymentAddress(address paymentAddress);

    error AuctionClosed();

    error AuctionNotMade(bytes32 auctionHash);

    error AlreadyClaimed();

    error AuctionHasNotClosed();

    error CallerNotBeneficiary();

    error InvalidBid();

    error AuctionUnsuccessful();

    error CannotWithdraw();

    error ZeroAmount();

    error AlreadyWithdrawn();

    /*----------------------------------------------------------*|
    |*  # AUCTION FUNCTIONS                                     *|
    |*----------------------------------------------------------*/

    // Assumes prior approval to transfer `id` of `targetAddress` to this address.
    function createAuction(bytes memory auctionData) external returns (bytes32 auctionHash) {
        // Decode auction data
        Auction memory auction = decodeAuctionData(auctionData);

        // Auction hash
        auctionHash = keccak256(abi.encode(auction));

        // Check caller is the proposer
        if (msg.sender != auction.proposer) revert CallerIsNotStatedProposer({ proposer: auction.proposer });

        // Check start time validity
        if (auction.startTime < block.timestamp) revert InvalidAuctionStartTime({ time: auction.startTime });

        // Check duration validity
        if (auction.duration > MAXIMUM_DURATION) revert InvalidAuctionDuration({ duration: auction.duration });

        // Check payment address
        if (auction.paymentAddress == address(0)) {
            revert InvalidPaymentAddress({ paymentAddress: auction.paymentAddress });
        }

        // Transfer ERC-721 to the vault
        _pullERC721(auction.targetAddress, auction.tokenId, auction.proposer);

        // Auction is made
        auctionsMade[auctionHash] = true;
    }

    // Make sure to:
    //  - update bid for address. If bid exists, only transfer the diff.

    // Conceptually:
    //  - assume `value` is the price, not the incremental amount the bidder wants to add to their bid.
    function bid(bytes memory auctionData, inEuint128 memory value) external {
        // Decode auction data
        Auction memory auction = decodeAuctionData(auctionData);

        // Auction hash
        bytes32 auctionHash = keccak256(abi.encode(auction));

        // Check auction is made
        if (!auctionsMade[auctionHash]) revert AuctionNotMade({ auctionHash: auctionHash });

        // Check auction is on
        if (block.timestamp < auction.startTime || block.timestamp > auction.startTime + auction.duration) {
            revert AuctionClosed();
        }

        // Check that the new bid is greater than the previous one (if it exists, otherwise 0).
        euint128 cypherPreviousBid = bidsPerAddr[msg.sender];
        euint128 cypherNewBid = FHE.asEuint128(value);
        if (FHE.decrypt(cypherPreviousBid.gte(cypherNewBid))) revert InvalidBid();

        // Calcualte the bid diff - this is the shielded ERC-20 transfer amount.
        // Maximum amount should be equal to the `cypherNewBid`.
        // euint128 cypherBidDiff = cypherNewBid.sub(cypherPreviousBid);

        // Todo:
        //  - transfer `cypherBidDiff` amount of shield ERC-20 token to this contract.
        //   - @question Adapt the Vault to incorporate this?
        // {Transfer shielded ERC-20 here}
        //  - @question: is the `FHERC20` impl okay for our use? I'm unsure about the `_spendAllowance` function.

        // Update bid for the calling address
        bidsPerAddr[msg.sender] = cypherNewBid;

        // Compare to highest bids
        Bids storage bids_ = bids[auctionHash];
        // If greater than highest bid
        if (FHE.decrypt(cypherNewBid.gt(bids_.bid1))) {
            // Update highest bid
            bids_.bid1 = cypherNewBid;
            // Update beneficiary
            beneficiary[auctionHash] = msg.sender;
        } else if (FHE.decrypt(cypherNewBid.gt(bids_.bid2))) {
            // Update second highest bid
            bids_.bid2 = cypherNewBid;
        }
    }

    // intended to be used by the highest bidder (beneficiary) of a completed auction
    // claims the NFT asset & transfers the highest and second highest bid diffs back to beneficiary.
    function claim(bytes memory auctionData) external {
        // Decode auction data
        Auction memory auction = decodeAuctionData(auctionData);

        // Auction hash
        bytes32 auctionHash = keccak256(abi.encode(auction));

        // Check the asset has not been claimed successfully
        if (claimed[auctionHash]) revert AlreadyClaimed();

        // Check the auction is over
        if (block.timestamp < auction.startTime + auction.duration) revert AuctionHasNotClosed();

        // Check the caller is the beneficiary
        if (msg.sender != beneficiary[auctionHash]) revert CallerNotBeneficiary();

        // Check that the auction was successful: second highest bid is greater than the reserve price
        Bids memory b = bids[auctionHash];
        if (FHE.decrypt(b.bid2.lt(FHE.asEuint128(auction.reservePrice)))) {
            revert AuctionUnsuccessful();
        }

        // Update claimed
        claimed[auctionHash] = true;

        // @note I don't think the below is necessary if there is a caller != beneficiary check in `withdraw`
        //        // Update beneficiary shield ERC-20 bid balance (so they can't `withdraw`) -- extra safety measure
        //        bidsPerAddr[msg.sender] = FHE.asEuint128(0);

        // Beneficiary pays second highest bid, transfer diff shielded ERC-20 tokens
        // euint128 diff = b.bid1.sub(b.bid2);
        // {todo Transfer `diff` amount of shield ERC-20 tokens to the msg.sender here}

        // Transfer asset to the beneficiary
        _pushERC721(auction.targetAddress, auction.tokenId, msg.sender);
    }

    // intended to be used by the auction's proposer OR bidders to withdraw shielded ERC-20 tokens
    function withdraw(bytes memory auctionData) external {
        // Decode auction data
        Auction memory auction = decodeAuctionData(auctionData);

        // Auction hash
        bytes32 auctionHash = keccak256(abi.encode(auction));

        // Check that the caller is not the beneficiary
        if (msg.sender == beneficiary[auctionHash]) revert CannotWithdraw();

        // Check the auction is over
        if (block.timestamp < auction.startTime + auction.duration) revert AuctionHasNotClosed();

        // Check there are tokens to be withdrawn
        euint128 withdrawAmount = bidsPerAddr[msg.sender];
        if (FHE.decrypt(withdrawAmount.eq(FHE.asEuint128(0)))) revert ZeroAmount();

        // Update callers shield ERC-20 bid balance
        bidsPerAddr[msg.sender] = FHE.asEuint128(0);

        // Transfer `withdrawAmount` amount of shielded ERC-20 tokens to the caller
        // todo implement transfer here.
    }

    function withdrawProposer(bytes memory auctionData) external {
        // Decode auction data
        Auction memory auction = decodeAuctionData(auctionData);

        // Auction hash
        bytes32 auctionHash = keccak256(abi.encode(auction));

        // Check the asset has not been withdrawn successfully
        if (withdrawn[auctionHash]) revert AlreadyWithdrawn();

        // Check the auction is over
        if (block.timestamp < auction.startTime + auction.duration) revert AuctionHasNotClosed();

        // Check the caller is the auction proposer
        if (msg.sender != auction.proposer) revert CallerNotBeneficiary();

        // Check that the auction was successful: second highest bid is greater than the reserve price
        Bids memory b = bids[auctionHash];
        if (FHE.decrypt(b.bid2.lt(FHE.asEuint128(auction.reservePrice)))) {
            revert AuctionUnsuccessful();
        }

        // Update withdrawn
        withdrawn[auctionHash] = true;

        // Transfer shield ERC-20 tokens to the proposer
        // euint128 bidPrice = bids[auctionHash].bid2;
        // todo transfer `bidPrice` amount of shield ERC-20 tokens to the proposer.
    }

    function encodeAuctionData(Auction calldata params) external pure returns (bytes memory) {
        return abi.encode(params);
    }

    function decodeAuctionData(bytes memory auctionData) public pure returns (Auction memory) {
        return abi.decode(auctionData, (Auction));
    }
}