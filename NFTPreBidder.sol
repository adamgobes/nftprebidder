pragma solidity 0.8.10;

import {Loan} from "src/NFTLoanFacilitator.sol";
import "../interfaces/INFTPreBidder.sol";
import "../interfaces/INFTLoanFacilitator.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {SafeTransferLib, ERC20} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {NFTLoanFacilitator} from "../NFTLoanFacilitator.sol";

struct Bid {
    uint16 minInterestRate;
    uint32 maxDurationSeconds;
    address bidder;
    address collateralContractAddress;
    address loanAssetContractAddress;
    uint256 maxLoanAmount;
    int256 collateralTokenId;
}

contract NFTPreBidder is Ownable, INFTPreBidder {
    using SafeTransferLib for ERC20;

    INFTLoanFacilitator facilitator;

    /// @dev tracks bid count
    uint256 private _nonce;

    mapping(uint256 => Bid) public _bidInfo;

    constructor(address _manager, address _facilitator) {
        transferOwnership(_manager);
        facilitator = INFTLoanFacilitator(_facilitator);
    }

    // ==== modifiers ====

    modifier bidExists(uint256 bidId) {
        require(
            bidId <= _nonce && _bidInfo[bidId].bidder != address(0),
            "NFTPreBidder: bid does not exist"
        );
        _;
    }

    modifier collateralAndLoanAssetMatch(uint256 bidId, uint256 loanId) {
        Bid memory bid = _bidInfo[bidId];
        (
            ,
            ,
            ,
            ,
            address collateralAddressFromLoan,
            address loanAssetAddressFromLoan,
            ,
            ,
            uint256 tokenIdFromLoan
        ) = facilitator.loanInfo(loanId);

        require(
            bid.loanAssetContractAddress == loanAssetAddressFromLoan,
            "NFTPreBidder: Fulfilling bid with incorrect loan asset"
        );
        require(
            bid.collateralContractAddress == collateralAddressFromLoan,
            "NFTPreBidder: Fulfilling bid with incorrect collateral address"
        );

        if (bid.collateralTokenId >= 0) {
            require(
                tokenIdFromLoan == uint256(bid.collateralTokenId),
                "NFTPreBidder: Fulfilling bid with incorrect tokenId"
            );
        }
        _;
    }

    // === view ===

    /// See {INFTPreBidder-bidInfo}.
    function bidInfo(uint256 bidId)
        external
        view
        override
        bidExists(bidId)
        returns (
            address bidder,
            address collateralContractAddress,
            int256 collateralTokenId,
            address loanAssetContractAddress,
            uint16 minInterestRate,
            uint256 maxDurationSeconds,
            uint256 maxLoanAmount
        )
    {
        Bid memory bid = _bidInfo[bidId];
        return (
            bid.bidder,
            bid.collateralContractAddress,
            bid.collateralTokenId,
            bid.loanAssetContractAddress,
            bid.minInterestRate,
            bid.maxDurationSeconds,
            bid.maxLoanAmount
        );
    }

    // ==== state changing ====

    /// See {INFTPreBidder-createBidForNFT}.
    function createBidForNFT(
        address collateralContractAddress,
        int256 collateralTokenId,
        address loanAssetContractAddress,
        uint16 minInterestRate,
        uint256 maxLoanAmount,
        uint32 maxDurationSeconds
    ) external override returns (uint256 id) {
        id = ++_nonce;
        Bid storage bid = _bidInfo[id];
        bid.bidder = msg.sender;
        bid.collateralContractAddress = collateralContractAddress;
        bid.collateralTokenId = collateralTokenId;

        bid.minInterestRate = minInterestRate;
        bid.loanAssetContractAddress = loanAssetContractAddress;
        bid.maxLoanAmount = maxLoanAmount;
        bid.maxDurationSeconds = maxDurationSeconds;

        emit CreateBid(
            id,
            msg.sender,
            collateralContractAddress,
            collateralTokenId,
            loanAssetContractAddress,
            minInterestRate,
            maxLoanAmount,
            maxDurationSeconds
        );
    }

    /// See {INFTPreBidder-fulfillBid}.
    function fulfillBid(uint256 bidId, uint256 loanId)
        external
        override
        bidExists(bidId)
        collateralAndLoanAssetMatch(bidId, loanId)
    {
        Bid memory bid = _bidInfo[bidId];

        ERC20(bid.loanAssetContractAddress).approve(
            address(facilitator),
            type(uint256).max
        );

        _fulfillBid(bidId, loanId);
    }

    /// See {INFTPreBidder-fulfillBid}.
    function fulfillBidWithNoApprovals(uint256 bidId, uint256 loanId)
        external
        override
        bidExists(bidId)
        collateralAndLoanAssetMatch(bidId, loanId)
    {
        _fulfillBid(bidId, loanId);
    }

    function cancelBid(uint256 bidId) external bidExists(bidId) {
        delete _bidInfo[bidId];
    }

    // === internal ===

    function _fulfillBid(uint256 bidId, uint256 loanId) private {
        Bid memory bid = _bidInfo[bidId];

        ERC20(bid.loanAssetContractAddress).safeTransferFrom(
            bid.bidder,
            address(this),
            bid.maxLoanAmount
        );

        // underwrite loan on behalf of the bidder
        facilitator.underwriteLoan(
            loanId,
            bid.minInterestRate,
            bid.maxLoanAmount,
            bid.maxDurationSeconds,
            bid.bidder
        );

        delete _bidInfo[bidId];

        emit FulfillBid(bidId, msg.sender, loanId);
    }
}
