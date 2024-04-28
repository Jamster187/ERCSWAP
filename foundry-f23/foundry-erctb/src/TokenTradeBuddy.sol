// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Interfaces to interact with ERC721 (NFT) and ERC20 (token) smart contracts.
interface IERC721 {
    function ownerOf(uint256 tokenId) external view returns (address);
    function transferFrom(address from, address to, uint256 tokenId) external;
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

// Main contract for managing the secure swap of assets between two parties.
contract TTBContract {
    address public owner;  // Initialize owner address variable for the deployer of the contract

    // Enumeration of possible states of a trade.
    enum TradeState {
        AssetSetup,           // Initial state, setting up assets for trade.
        PendingOffer,         // Ready to accept deposits.
        ProposerDeposited,    // Proposer has deposited their assets.
        ReceiverDeposited,    // Receiver has deposited their assets.
        BothDeposited,        // Both parties have deposited their assets.
        AssetsTransferred,    // Assets have been swapped successfully.
        TradeCancelled        // Trade has been cancelled.
    }

    // Represents an NFT asset in the trade.
    struct NFTAsset {
        address nftAddress;   // Address of the NFT contract.
        uint256 nftId;        // Token ID of the NFT.
        bool deposited;       // Whether the NFT has been deposited.
    }

    // Represents a token asset in the trade.
    struct CoinAsset {
        address coinAddress;  // Address of the token contract.
        uint256 coinAmount;   // Amount of tokens.
        bool deposited;       // Whether the tokens have been deposited.
    }

    // Represents a trading participant (either proposer or receiver).
    struct Participant {
        address addr;         // Address of the participant.
        NFTAsset[] nftAssets; // List of NFT assets the participant will trade.
        CoinAsset[] coinAssets; // List of token assets the participant will trade.
    }

    Participant public proposer;  // The proposing participant.
    Participant public receiver;  // The receiving participant.
    TradeState public currentTradeState;  // Current state of the trade.

    mapping(address => uint256) public seedETHDeposits;  // Mapping of addresses to their ETH deposits.

    constructor() {
        owner = msg.sender;  // Set the owner to the deployer of the contract.
        currentTradeState = TradeState.AssetSetup;  // Initialize state to AssetSetup.
    }

    // Modifier to restrict function access to the contract owner.
    modifier onlyOwner() {
        require(msg.sender == owner, "Not authorized, owner only");
        _;
    }

    // Modifier to restrict function access to the trading participants.
    modifier onlyTraders() {
        require(msg.sender == proposer.addr || msg.sender == receiver.addr, "Not trader");
        _;
    }

    // Modifier to restrict function access to the contract owner or the trading participants.
    modifier onlyAuthorized () {
        require(msg.sender == owner || msg.sender == proposer.addr || msg.sender == receiver.addr, "Not authorized");
        _;
    }

    // Function to setup the assets for a participant.
    // `isProposer` determines whether the assets are for the proposer or the receiver.
    function setParticipantAssets(
        address participantAddress,
        address[] calldata nftAddresses,
        uint256[] calldata nftIds,
        address[] calldata coinAddresses,
        uint256[] calldata coinAmounts,
        bool isProposer
    ) public onlyOwner {
        require(currentTradeState == TradeState.AssetSetup, "Can only setup assets in AssetSetup state");
        require(nftAddresses.length == nftIds.length, "NFT addresses and IDs length mismatch");
        require(coinAddresses.length == coinAmounts.length, "Coin addresses and amounts length mismatch");

        Participant storage participant = isProposer ? proposer : receiver;
        participant.addr = participantAddress;

        for (uint256 i = 0; i < nftAddresses.length; i++) {
            participant.nftAssets.push(NFTAsset({
                nftAddress: nftAddresses[i],
                nftId: nftIds[i],
                deposited: false
            }));
        }

        for (uint256 j = 0; j < coinAddresses.length; j++) {
            participant.coinAssets.push(CoinAsset({
                coinAddress: coinAddresses[j],
                coinAmount: coinAmounts[j],
                deposited: false
            }));
        }
    }

    // Function to manually finish the asset setup and transition to the next state.
    function finishAssetSetup() public onlyOwner {
        require(currentTradeState == TradeState.AssetSetup, "Can only finish setup in AssetSetup state");
        currentTradeState = TradeState.PendingOffer;
    }

    // Function for participants to deposit ETH as seed money or guarantee.
    function depositSeedETH() public payable onlyTraders {
        require(currentTradeState != TradeState.AssetSetup, "Not allowed in AssetSetup state");
        seedETHDeposits[msg.sender] += msg.value;
    }

    // Function for participants to withdraw their deposited ETH.
    function withdrawSeedETH(uint256 amount) public onlyTraders {
        require(seedETHDeposits[msg.sender] >= amount, "Withdraw amount exceeds deposit");
        payable(msg.sender).transfer(amount);
        seedETHDeposits[msg.sender] -= amount;
    }

    // Function for participants to deposit their designated assets.
    function depositAssets() public onlyTraders {
        require(currentTradeState == TradeState.PendingOffer || currentTradeState == TradeState.ProposerDeposited || currentTradeState == TradeState.ReceiverDeposited, "Trade cannot proceed");
        Participant storage participant = msg.sender == proposer.addr ? proposer : receiver;

        for (uint i = 0; i < participant.nftAssets.length; i++) {
            if (!participant.nftAssets[i].deposited) {
                IERC721 nftContract = IERC721(participant.nftAssets[i].nftAddress);
                nftContract.transferFrom(msg.sender, address(this), participant.nftAssets[i].nftId);
                participant.nftAssets[i].deposited = true;
            }
        }

        for (uint j = 0; j < participant.coinAssets.length; j++) {
            if (!participant.coinAssets[j].deposited) {
                IERC20 tokenContract = IERC20(participant.coinAssets[j].coinAddress);
                tokenContract.transferFrom(msg.sender, address(this), participant.coinAssets[j].coinAmount);
                participant.coinAssets[j].deposited = true;
            }
        }

        updateTradeState();
        // If both parties have deposited, perform the swap immediately.
        if (currentTradeState == TradeState.BothDeposited) {
            performAssetSwap();
        }
    }

    // Function for participants to withdraw their assets if the trade is cancelled or not completed.
    function withdrawAssets() public onlyTraders {
        require(currentTradeState != TradeState.AssetsTransferred && currentTradeState != TradeState.TradeCancelled, "Trade completed or cancelled");
        Participant storage participant = msg.sender == proposer.addr ? proposer : receiver;
        executeAssetReturn(participant);
    }

    // Function to cancel the trade and return assets to both participants.
    function cancelTrade() public onlyAuthorized {
        require(currentTradeState != TradeState.TradeCancelled, "Trade already cancelled");
        currentTradeState = TradeState.TradeCancelled;
        executeAssetReturn(proposer);
        executeAssetReturn(receiver);
        if (seedETHDeposits[proposer.addr] > 0) {
            payable(proposer.addr).transfer(seedETHDeposits[proposer.addr]);
            seedETHDeposits[proposer.addr] = 0;
        }
    }

    // Internal function to handle the return of assets to a participant.
    function executeAssetReturn(Participant storage participant) private {
        for (uint i = 0; i < participant.nftAssets.length; i++) {
            if (participant.nftAssets[i].deposited) {
                IERC721 nftContract = IERC721(participant.nftAssets[i].nftAddress);
                nftContract.transferFrom(address(this), participant.addr, participant.nftAssets[i].nftId);
                participant.nftAssets[i].deposited = false;
            }
        }
        for (uint j = 0; j < participant.coinAssets.length; j++) {
            if (participant.coinAssets[j].deposited) {
                IERC20 tokenContract = IERC20(participant.coinAssets[j].coinAddress);
                tokenContract.transfer(participant.addr, participant.coinAssets[j].coinAmount);
                participant.coinAssets[j].deposited = false;
            }
        }
    }

    // Function to perform the actual asset swap between participants.
    function performAssetSwap() private {
        // Transfer all NFTs and tokens from the proposer to the receiver.
        swapAssets(proposer, receiver);
        // Transfer all NFTs and tokens from the receiver to the proposer.
        swapAssets(receiver, proposer);
        // Update the state to AssetsTransferred to indicate successful swap.
        currentTradeState = TradeState.AssetsTransferred;
    }

    // Helper function to transfer assets between two participants.
    function swapAssets(Participant storage from, Participant storage to) private {
        for (uint i = 0; i < from.nftAssets.length; i++) {
            if (from.nftAssets[i].deposited) {
                IERC721 nftContract = IERC721(from.nftAssets[i].nftAddress);
                nftContract.transferFrom(address(this), to.addr, from.nftAssets[i].nftId);
            }
        }
        for (uint j = 0; j < from.coinAssets.length; j++) {
            if (from.coinAssets[j].deposited) {
                IERC20 tokenContract = IERC20(from.coinAssets[j].coinAddress);
                tokenContract.transfer(to.addr, from.coinAssets[j].coinAmount);
            }
        }
    }

    // Internal function to update the state of the trade based on the assets deposited.
    function updateTradeState() private {
        bool proposerAllDeposited = areAllAssetsDeposited(proposer);
        bool receiverAllDeposited = areAllAssetsDeposited(receiver);

        if (proposerAllDeposited && receiverAllDeposited) {
            currentTradeState = TradeState.BothDeposited;
        } else if (proposerAllDeposited) {
            currentTradeState = TradeState.ProposerDeposited;
        } else if (receiverAllDeposited) {
            currentTradeState = TradeState.ReceiverDeposited;
        } else {
            currentTradeState = TradeState.PendingOffer;
        }
    }

    // Internal function to check if all assets of a participant have been deposited.
    function areAllAssetsDeposited(Participant storage participant) private view returns (bool) {
        for (uint i = 0; i < participant.nftAssets.length; i++) {
            if (!participant.nftAssets[i].deposited) return false;
        }
        for (uint j = 0; j < participant.coinAssets.length; j++) {
            if (!participant.coinAssets[j].deposited) return false;
        }
        return true;
    }
}
