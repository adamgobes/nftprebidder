pragma solidity 0.8.10;

import {DSTest} from "ds-test/test.sol";
import {Vm} from "forge-std/Vm.sol";

import {NFTPreBidder} from "src/plugins/NFTPreBidder.sol";
import {NFTLoanFacilitator} from "src/NFTLoanFacilitator.sol";
import {NFTLoanFacilitatorFactory} from "./NFTLoanFacilitatorFactory.sol";
import {BorrowTicket} from "src/BorrowTicket.sol";
import {LendTicket} from "src/LendTicket.sol";
import {CryptoPunks} from "./mocks/CryptoPunks.sol";
import {DAI} from "./mocks/DAI.sol";

import "./console.sol";

contract NFTPreBidderGasBenchmarkTest is DSTest {
    Vm vm = Vm(HEVM_ADDRESS);

    NFTPreBidder preBidder;
    NFTLoanFacilitator facilitator;

    address lender = address(1);
    address borrower = address(2);

    CryptoPunks punks = new CryptoPunks();
    DAI dai = new DAI();

    uint16 interestRate = 15;
    uint256 loanAmount = 1e20;
    uint32 loanDuration = 1000;

    uint256 tokenId;
    uint256 bidId;
    uint256 loanId;

    function setUp() public {
        NFTLoanFacilitatorFactory factory = new NFTLoanFacilitatorFactory();
        (, , facilitator) = factory.newFacilitator(address(this));
        preBidder = new NFTPreBidder(address(this), address(facilitator));

        vm.startPrank(borrower);
        tokenId = punks.mint();
        punks.approve(address(facilitator), tokenId);
        vm.stopPrank();

        vm.startPrank(lender);
        bidId = preBidder.createBidForNFT(
            address(punks),
            int256(tokenId),
            address(dai),
            interestRate,
            loanAmount,
            loanDuration
        );
        vm.startPrank(borrower);
        loanId = facilitator.createLoan(
            tokenId,
            address(punks),
            interestRate,
            loanAmount,
            address(dai),
            loanDuration,
            address(borrower)
        );

        vm.startPrank(lender);
        dai.mint(loanAmount, lender);
        dai.approve(address(preBidder), loanAmount);
        vm.stopPrank();
    }

    function testCreateBidForNFTGas() public {
        preBidder.createBidForNFT(
            address(punks),
            int256(tokenId),
            address(dai),
            interestRate,
            loanAmount,
            loanDuration
        );
    }

    function testFulfillBidGas() public {
        vm.startPrank(borrower);
        preBidder.fulfillBid(bidId, loanId);
    }

    function testCancelBidGas() public {
        preBidder.cancelBid(bidId);
    }
}

contract NFTPreBidderTest is DSTest {
    Vm vm = Vm(HEVM_ADDRESS);

    NFTPreBidder preBidder;

    NFTLoanFacilitator facilitator;
    BorrowTicket borrowTicket;
    LendTicket lendTicket;

    address lender = address(1);
    address borrower = address(2);

    CryptoPunks punks = new CryptoPunks();
    DAI dai = new DAI();

    uint16 interestRate = 15;
    uint256 loanAmount = 1e20;
    uint32 loanDuration = 1000;

    function setUp() public {
        NFTLoanFacilitatorFactory factory = new NFTLoanFacilitatorFactory();
        (borrowTicket, lendTicket, facilitator) = factory.newFacilitator(
            address(this)
        );
        preBidder = new NFTPreBidder(address(this), address(facilitator));
    }

    function testCreateBidSuccessful() public {
        vm.startPrank(lender);

        int256 tokenId = 1;
        uint256 bidId = preBidder.createBidForNFT(
            address(punks),
            tokenId,
            address(dai),
            interestRate,
            loanAmount,
            loanDuration
        );
        (
            address bidder,
            address collateralContractAddress,
            int256 collateralTokenId,
            address loanAssetContractAddress,
            uint16 minPerSecondInterestRate,
            uint256 maxDurationSeconds,
            uint256 maxLoanAmount
        ) = preBidder.bidInfo(bidId);
        assertEq(bidder, lender);
        assertEq(collateralContractAddress, address(punks));
        assertEq(collateralTokenId, tokenId);
        assertEq(loanAssetContractAddress, address(dai));
        assertEq(minPerSecondInterestRate, interestRate);
        assertEq(maxDurationSeconds, loanDuration);
        assertEq(maxLoanAmount, loanAmount);
    }

    function testFulfillBidSuccessfulWithSpecifiedTokenId() public {
        uint256 tokenId = setUpWithPunk(borrower);
        setUpWithDai(lender);

        uint256 lenderBalance = dai.balanceOf(lender);
        uint256 borrowerBalance = dai.balanceOf(borrower);

        vm.startPrank(lender);
        uint256 bidId = preBidder.createBidForNFT(
            address(punks),
            int256(tokenId),
            address(dai),
            interestRate,
            loanAmount,
            loanDuration
        );
        vm.startPrank(borrower);
        uint256 loanId = facilitator.createLoan(
            tokenId,
            address(punks),
            interestRate,
            loanAmount,
            address(dai),
            loanDuration,
            address(borrower)
        );

        vm.startPrank(borrower);
        preBidder.fulfillBid(bidId, loanId);

        assertEq(punks.ownerOf(tokenId), address(facilitator));
        assertEq(dai.balanceOf(lender), lenderBalance - loanAmount);
        assertEq(
            dai.balanceOf(borrower),
            borrowerBalance + loanAmount - calculateTake(loanAmount)
        );
        assertEq(borrowTicket.ownerOf(loanId), borrower);
        assertEq(lendTicket.ownerOf(loanId), lender);
    }

    function testFulfillBidSuccessfulWithUnspecifiedTokenId() public {
        uint256 tokenId = setUpWithPunk(borrower);
        setUpWithDai(lender);

        uint256 lenderBalance = dai.balanceOf(lender);
        uint256 borrowerBalance = dai.balanceOf(borrower);

        vm.startPrank(lender);
        uint256 bidId = preBidder.createBidForNFT(
            address(punks),
            -1, // tokenId not specified
            address(dai),
            interestRate,
            loanAmount,
            loanDuration
        );
        vm.startPrank(borrower);
        uint256 loanId = facilitator.createLoan(
            tokenId,
            address(punks),
            interestRate,
            loanAmount,
            address(dai),
            loanDuration,
            address(borrower)
        );

        preBidder.fulfillBid(bidId, loanId);

        assertEq(punks.ownerOf(tokenId), address(facilitator));
        assertEq(dai.balanceOf(lender), lenderBalance - loanAmount);
        assertEq(
            dai.balanceOf(borrower),
            borrowerBalance + loanAmount - calculateTake(loanAmount)
        );
        assertEq(borrowTicket.ownerOf(loanId), borrower);
        assertEq(lendTicket.ownerOf(loanId), lender);
    }

    function testFulfillBidFailsIfWrongTokenId() public {
        uint256 desiredTokenId = 1;
        vm.startPrank(lender);
        uint256 bidId = preBidder.createBidForNFT(
            address(punks),
            int256(desiredTokenId),
            address(dai),
            interestRate,
            loanAmount,
            loanDuration
        );

        uint256 borrowerTokenId = setUpWithPunk(borrower);
        vm.startPrank(borrower);
        uint256 loanId = facilitator.createLoan(
            borrowerTokenId,
            address(punks),
            interestRate,
            loanAmount,
            address(dai),
            loanDuration,
            address(borrower)
        );

        vm.expectRevert("NFTPreBidder: Fulfilling bid with incorrect tokenId");
        preBidder.fulfillBid(bidId, loanId);

        vm.expectRevert("NFTPreBidder: Fulfilling bid with incorrect tokenId");
        preBidder.fulfillBidWithNoApprovals(bidId, loanId);
    }

    function testFulfillBidRevertsIfLenderDoesNotHaveFunds() public {
        uint256 tokenId = setUpWithPunk(borrower);
        vm.startPrank(lender);
        uint256 bidId = preBidder.createBidForNFT(
            address(punks),
            int256(tokenId),
            address(dai),
            interestRate,
            loanAmount,
            loanDuration
        );
        vm.startPrank(borrower);
        uint256 loanId = facilitator.createLoan(
            tokenId,
            address(punks),
            interestRate,
            loanAmount,
            address(dai),
            loanDuration,
            address(borrower)
        );

        // approve spending so we don't get allowance revert
        vm.startPrank(lender);
        dai.approve(address(preBidder), loanAmount);

        vm.startPrank(borrower);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        preBidder.fulfillBid(bidId, loanId);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        preBidder.fulfillBidWithNoApprovals(bidId, loanId);
    }

    function testFulfillBidWithNoApprovalsSuccessful() public {
        uint256 tokenId = setUpWithPunk(borrower);
        setUpWithDai(lender);

        uint256 lenderBalance = dai.balanceOf(lender);
        uint256 borrowerBalance = dai.balanceOf(borrower);

        vm.startPrank(lender);
        uint256 bidId = preBidder.createBidForNFT(
            address(punks),
            int256(tokenId),
            address(dai),
            interestRate,
            loanAmount,
            loanDuration
        );
        vm.startPrank(borrower);
        uint256 loanId = facilitator.createLoan(
            tokenId,
            address(punks),
            interestRate,
            loanAmount,
            address(dai),
            loanDuration,
            address(borrower)
        );

        // a client would only call this if NFTPreBidder contract has approved NFTLoanFacilitator to transfer NFT being collateralized AND loan asset ERC20
        vm.startPrank(address(preBidder));
        punks.setApprovalForAll(address(facilitator), true);
        dai.approve(address(facilitator), type(uint256).max);

        vm.startPrank(borrower);
        preBidder.fulfillBidWithNoApprovals(bidId, loanId);

        assertEq(punks.ownerOf(tokenId), address(facilitator));
        assertEq(dai.balanceOf(lender), lenderBalance - loanAmount);
        assertEq(
            dai.balanceOf(borrower),
            borrowerBalance + loanAmount - calculateTake(loanAmount)
        );
        assertEq(borrowTicket.ownerOf(loanId), borrower);
        assertEq(lendTicket.ownerOf(loanId), lender);
    }

    function testCancelBidSuccessful() public {
        uint256 tokenId = setUpWithPunk(borrower);
        vm.startPrank(lender);
        uint256 bidId = preBidder.createBidForNFT(
            address(punks),
            int256(tokenId),
            address(dai),
            interestRate,
            loanAmount,
            loanDuration
        );

        // let's say lender wants to cancel their bid
        preBidder.cancelBid(bidId);

        vm.startPrank(borrower);
        vm.expectRevert("NFTPreBidder: bid does not exist");
        preBidder.fulfillBid(bidId, 1);
    }

    function setUpWithPunk(address addr) public returns (uint256 tokenId) {
        vm.startPrank(addr);
        tokenId = punks.mint();

        punks.approve(address(facilitator), tokenId);
        vm.stopPrank();
    }

    function setUpWithDai(address addr) public {
        vm.startPrank(addr);
        dai.mint(loanAmount, addr);
        dai.approve(address(preBidder), loanAmount);
        vm.stopPrank();
    }

    function calculateTake(uint256 amount) public returns (uint256) {
        return
            (amount * facilitator.originationFeePercent()) /
            facilitator.SCALAR();
    }
}
