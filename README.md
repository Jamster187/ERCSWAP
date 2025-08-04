# ValidatedSwapEscrow

This is a basic Solidity smart contract that lets two specific Ethereum addresses swap NFTs and ERC20 tokens. Each participant must first deposit their listed assets, and once both have done so, the contract transfers the assets to the other party.

This project was created to learn more about interacting with ERC721 and ERC20 contracts, working with structs, and managing on-chain asset transfers.

## How It Works

- The contract defines two participants: `player1` and `player2`, each with their own NFTs and ERC20 tokens to deposit.
- Each participant must deposit all of their listed NFTs and tokens into the contract.
- After both participants have finished depositing, a function can be called to check the deposits and perform the swap.

## Features

- Handles deposits for multiple NFTs and ERC20 tokens for both participants
- Transfers assets only after both sides have completed their deposits
- Keeps track of which NFTs have already been deposited to avoid duplicates
- Uses basic Solidity concepts like structs, mappings, arrays, and interfaces

## Important Notes

- The participant addresses and their assets are hardcoded in the constructor
- Only those two addresses can use the contract
- There is no cancel or refund functionality
- There are no admin or pause functions
- The contract assumes all token contracts follow the ERC721 and ERC20 standards

## Main Functions

### `depositNFT(uint256 nftIndex)`
The participant deposits an NFT from their list by index.

### `depositERC20()`
The participant deposits all of their listed ERC20 tokens.

### `checkDeposits()`
Checks if both participants have deposited everything. If so, it calls the internal `executeSwap()` function.

### `executeSwap()`
Transfers the deposited NFTs and tokens from each participant to the other.

## Why I Built This

This was one of my first Solidity projects. I wanted to get hands-on practice with calling external contracts (like NFT and token contracts), using structs to organize participant data, and writing a simple flow for an on-chain exchange.

## Things I Would Improve Next Time

- Add support for more users instead of just two hardcoded ones
- Allow dynamic configuration of assets
- Add timeout or cancel options
- Write better checks and error handling
- Look into best practices for handling deposits and swaps safely

## License

MIT
