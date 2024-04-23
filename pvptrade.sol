// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC721 {
    function ownerOf(uint256 tokenId) external view returns (address);
    function transferFrom(address from, address to, uint256 tokenId) external;
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

contract ValidatedSwapEscrow {
    address public owner;

    struct NFTAsset {
        address nftAddress;
        uint256 nftId;
        bool deposited;  // Add 'deposited' flag to track individual NFT deposit status
    }

    struct CoinAsset {
        address coinAddress;
        uint256 coinAmount;
    }

    struct Participant {
        address addr;
        NFTAsset[] nftAssets;
        CoinAsset[] coinAssets;
        bool hasDepositedCoins;
    }

    Participant public player1;
    Participant public player2;

    constructor() {
        owner = msg.sender;
        // Initialize player1 assets
        player1.addr = 0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2;
        player1.nftAssets.push(NFTAsset(0x8B801270f3e02eA2AACCf134333D5E5A019eFf42, 1, false));
        player1.nftAssets.push(NFTAsset(0x8B801270f3e02eA2AACCf134333D5E5A019eFf42, 2, false));
        player1.coinAssets.push(CoinAsset(0xF27374C91BF602603AC5C9DaCC19BE431E3501cb, 999));

        // Initialize player2 assets
        player2.addr = 0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db;
        player2.nftAssets.push(NFTAsset(0xd16B472C1b3AB8bc40C1321D7b33dB857e823f01, 1, false));
        player2.nftAssets.push(NFTAsset(0xd16B472C1b3AB8bc40C1321D7b33dB857e823f01, 2, false));
        player2.coinAssets.push(CoinAsset(0x26b989b9525Bb775C8DEDf70FeE40C36B397CE67, 1998));
    }

    // Participants call this to deposit NFTs
    function depositNFT(uint256 nftIndex) public {
        Participant storage participant = msg.sender == player1.addr ? player1 : player2;
        require(!participant.nftAssets[nftIndex].deposited, "This NFT has already been deposited");
        IERC721 nftContract = IERC721(participant.nftAssets[nftIndex].nftAddress);
        nftContract.transferFrom(msg.sender, address(this), participant.nftAssets[nftIndex].nftId);
        participant.nftAssets[nftIndex].deposited = true;
    }

    // Participants call this to deposit ERC20 tokens
    function depositERC20() public {
        Participant storage participant = msg.sender == player1.addr ? player1 : player2;
        require(!participant.hasDepositedCoins, "Coins already deposited");
        for (uint i = 0; i < participant.coinAssets.length; i++) {
            IERC20 tokenContract = IERC20(participant.coinAssets[i].coinAddress);
            tokenContract.transferFrom(msg.sender, address(this), participant.coinAssets[i].coinAmount);
        }
        participant.hasDepositedCoins = true;
    }

    function checkDeposits() public {
        if (checkNFTDeposits(player1) && checkNFTDeposits(player2) &&
            checkCoinDeposits(player1) && checkCoinDeposits(player2)) {
            executeSwap();
        }
    }

    function checkNFTDeposits(Participant storage participant) private view returns (bool) {
        // Directly return true if there are no NFT assets to deposit.
        if (participant.nftAssets.length == 0) {
            return true;
        }

        // Loop through all NFT assets to check if each one has been deposited.
        for (uint i = 0; i < participant.nftAssets.length; i++) {
            if (!participant.nftAssets[i].deposited) {
                return false;  // If any NFT has not been deposited, return false.
            }
        }
        return true;  // Return true if all NFTs are deposited.
    }


    function checkCoinDeposits(Participant storage participant) private view returns (bool) {
        if (participant.coinAssets.length == 0) {
            return true;
        }

        for (uint i = 0; i < participant.coinAssets.length; i++) {
            if (IERC20(participant.coinAssets[i].coinAddress).balanceOf(address(this)) < participant.coinAssets[i].coinAmount) {
                return false;
            }
        }
        return true;
    }

    function executeSwap() private {
        transferAssets(player1, player2);
        transferAssets(player2, player1);
    }

    function transferAssets(Participant storage from, Participant storage to) private {
        for (uint i = 0; i < from.nftAssets.length; i++) {
            IERC721 nftContract = IERC721(from.nftAssets[i].nftAddress);
            nftContract.transferFrom(address(this), to.addr, from.nftAssets[i].nftId);
        }
        for (uint j = 0; j < from.coinAssets.length; j++) {
            IERC20 tokenContract = IERC20(from.coinAssets[j].coinAddress);
            tokenContract.transfer(to.addr, from.coinAssets[j].coinAmount);
        }
    }
}
