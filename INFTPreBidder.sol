pragma solidity 0.8.10;

interface INFTPreBidder {
    /**
     * @notice Emitted when the bid is created
     * @param id The id of the new bid
     * @param bidder msg.sender
     * @param collateralContract The contract address of the collateral NFT
     * @param collateralTokenId The token id of the collateral NFT, can be a negative number to indicate bidder doesn't care which token ID
     * @param loanAssetContract The contract address of the loan asset
     * @param minInterestRate The min per second interest rate, scaled by SCALAR
     * @param maxLoanAmount maximum loan amount
     * @param maxDurationSeconds maximum loan duration in seconds
     */
    event CreateBid(
        uint256 indexed id,
        address indexed bidder,
        address collateralContract,
        int256 collateralTokenId,
        address loanAssetContract,
        uint256 minInterestRate,
        uint256 maxLoanAmount,
        uint256 maxDurationSeconds
    );

    /**
     * @notice Creates on-chain bid representing users desire to lend against a particular NFT
     * @param collateralContractAddress The contract address of the collateral NFT
     * @param collateralTokenId The token id of the collateral NFT, can be a negative number to indicate bidder doesn't care which token ID
     * @param loanAssetContractAddress The contract address of the loan asset
     * @param minInterestRate The min per second interest rate, scaled by SCALAR
     * @param maxLoanAmount maximum loan amount
     * @param maxDurationSeconds maximum loan duration in seconds
     * @return id of the created bid
     */
    function createBidForNFT(
        address collateralContractAddress,
        int256 collateralTokenId,
        address loanAssetContractAddress,
        uint16 minInterestRate,
        uint256 maxLoanAmount,
        uint32 maxDurationSeconds
    ) external returns (uint256 id);

    /**
     * @notice Emitted when the loan is created
     * @param id The id of the bid
     * @param fulfiller address of user who fulfilled bid
     */
    event FulfillBid(
        uint256 indexed id,
        address indexed fulfiller,
        uint256 loanId
    );

    /**
     * @notice Fulfills on-chain bid, approving facilitator to spend ERC20 to underwrite loan on behalf of initial bidder
     * @param bidId id of bid that the lender created
     @param loanId The loan from the facilitator that will be used to fulfill this bid
     */
    function fulfillBid(uint256 bidId, uint256 loanId) external;

    /**
     * @notice Fulfills on-chain bid, more gas efficient than fulfillBid, since it assumes NFTPreBidder has already approved ERC20 transfer from NFTLoanFacilitator
     * @param bidId id of bid that the lender created
     @param loanId The loan from the facilitator that will be used to fulfill this bid
     */
    function fulfillBidWithNoApprovals(uint256 bidId, uint256 loanId) external;

    /**
     * @notice returns the info for this bid
     * @param bidId The id of the bid
     * @return bidder Bidder who initiated the bid
     * @return collateralContractAddress The contract address of the NFT collateral
     * @return collateralTokenId The token ID of the NFT collateral
     * @return loanAssetContractAddress The contract address of the loan asset.
     * @return minInterestRate The per second interest rate, scaled by SCALAR
     * @return maxDurationSeconds The loan duration in seconds
     * @return maxLoanAmount The loan amount
     */
    function bidInfo(uint256 bidId)
        external
        view
        returns (
            address bidder,
            address collateralContractAddress,
            int256 collateralTokenId,
            address loanAssetContractAddress,
            uint16 minInterestRate,
            uint256 maxDurationSeconds,
            uint256 maxLoanAmount
        );

    /**
     * @notice deletes a bid, making it unable to be fulfilled
     * @param bidId The id of the bid
     */
    function cancelBid(uint256 bidId) external;
}
