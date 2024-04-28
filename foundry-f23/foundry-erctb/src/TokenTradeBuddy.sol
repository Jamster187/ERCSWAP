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
    address public s_owner;  // Owner of the contract, set during deployment

    enum TradeState {
        AssetSetup,
        PendingOffer,
        ProposerDeposited,
        ReceiverDeposited,
        BothDeposited,
        AssetsTransferred,
        TradeCancelled
    }

    struct NFTAsset {
        address nftAddress;
        uint256 nftId;
        bool deposited;
    }

    struct CoinAsset {
        address coinAddress;
        uint256 coinAmount;
        bool deposited;
    }

    struct Participant {
        address addr;
        NFTAsset[] nftAssets;
        CoinAsset[] coinAssets;
    }

    Participant public s_proposer;  // Proposing participant
    Participant public s_receiver;  // Receiving participant
    TradeState public s_currentTradeState;  // Current state of the trade

    mapping(address => uint256) public s_seedETHDeposits;  // Mapping of ETH deposits by address

    constructor() {
        s_owner = msg.sender;
        s_currentTradeState = TradeState.AssetSetup;
    }

    modifier onlyOwner() {
        require(msg.sender == s_owner, "Not authorized, owner only");
        _;
    }

    modifier onlyTraders() {
        require(msg.sender == s_proposer.addr || msg.sender == s_receiver.addr, "Not a trader");
        _;
    }

    modifier onlyAuthorized() {
        require(msg.sender == s_owner || msg.sender == s_proposer.addr || msg.sender == s_receiver.addr, "Not authorized");
        _;
    }

    function setParticipantAssets(
        address participantAddress,
        address[] calldata nftAddresses,
        uint256[] calldata nftIds,
        address[] calldata coinAddresses,
        uint256[] calldata coinAmounts,
        bool isProposer
    ) public onlyOwner {
        require(s_currentTradeState == TradeState.AssetSetup, "Setup assets only during AssetSetup state");
        require(nftAddresses.length == nftIds.length, "Mismatch in NFT addresses and IDs");
        require(coinAddresses.length == coinAmounts.length, "Mismatch in coin addresses and amounts");

        Participant storage participant = isProposer ? s_proposer : s_receiver;
        participant.addr = participantAddress;

        for (uint256 i = 0; i < nftAddresses.length; i++) {
            participant.nftAssets.push(NFTAsset(nftAddresses[i], nftIds[i], false));
        }

        for (uint256 j = 0; j < coinAddresses.length; j++) {
            participant.coinAssets.push(CoinAsset(coinAddresses[j], coinAmounts[j], false));
        }
    }

    function finishAssetSetup() public onlyOwner {
        require(s_currentTradeState == TradeState.AssetSetup, "Can only finish setup in AssetSetup state");
        s_currentTradeState = TradeState.PendingOffer;
    }

    function depositSeedETH() public payable onlyTraders {
        require(s_currentTradeState != TradeState.AssetSetup, "Not allowed in AssetSetup state");
        s_seedETHDeposits[msg.sender] += msg.value;
    }

    function withdrawSeedETH(uint256 amount) public onlyTraders {
        require(s_seedETHDeposits[msg.sender] >= amount, "Withdraw amount exceeds deposit");
        payable(msg.sender).transfer(amount);
        s_seedETHDeposits[msg.sender] -= amount;
    }

    function depositAssets() public onlyTraders {
        require(s_currentTradeState == TradeState.PendingOffer || s_currentTradeState == TradeState.ProposerDeposited || s_currentTradeState == TradeState.ReceiverDeposited, "Trade cannot proceed");
        Participant storage participant = msg.sender == s_proposer.addr ? s_proposer : s_receiver;

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
        if (s_currentTradeState == TradeState.BothDeposited) {
            performAssetSwap();
        }
    }

    function withdrawAssets() public onlyTraders {
        require(s_currentTradeState != TradeState.AssetsTransferred && s_currentTradeState != TradeState.TradeCancelled, "Trade completed or cancelled");
        Participant storage participant = msg.sender == s_proposer.addr ? s_proposer : s_receiver;
        executeAssetReturn(participant);
    }

    function cancelTrade() public onlyAuthorized {
        require(s_currentTradeState != TradeState.TradeCancelled, "Trade already cancelled");
        s_currentTradeState = TradeState.TradeCancelled;
        executeAssetReturn(s_proposer);
        executeAssetReturn(s_receiver);
        if (s_seedETHDeposits[s_proposer.addr] > 0) {
            payable(s_proposer.addr).transfer(s_seedETHDeposits[s_proposer.addr]);
            s_seedETHDeposits[s_proposer.addr] = 0;
        }
    }

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

    function performAssetSwap() private {
        swapAssets(s_proposer, s_receiver);
        swapAssets(s_receiver, s_proposer);
        s_currentTradeState = TradeState.AssetsTransferred;
    }

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

    function updateTradeState() private {
        bool proposerAllDeposited = areAllAssetsDeposited(s_proposer);
        bool receiverAllDeposited = areAllAssetsDeposited(s_receiver);

        if (proposerAllDeposited && receiverAllDeposited) {
            s_currentTradeState = TradeState.BothDeposited;
        } else if (proposerAllDeposited) {
            s_currentTradeState = TradeState.ProposerDeposited;
        } else if (receiverAllDeposited) {
            s_currentTradeState = TradeState.ReceiverDeposited;
        } else {
            s_currentTradeState = TradeState.PendingOffer;
        }
    }

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
