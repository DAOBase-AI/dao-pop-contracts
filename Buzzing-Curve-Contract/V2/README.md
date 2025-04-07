
# Bonding Curve Contract

The Bonding Curve Contract is a smart contract that implements an exponential bonding curve mechanism, allowing creators to issue tokens and provide auto liquidity in a fair and decentralized manner. The bonding curve enables token price to increase as more tokens are purchased, ensuring an efficient market-driven pricing mechanism.

## Intro

The Bonding Curve Contract provides a decentralized and fair method for token issuance using an exponential bonding curve. It automatically adjusts the token price based on demand and supply, and provides liquidity through an integrated liquidity pool.

This contract allows creators to set up token sales with transparent and dynamic pricing, rewarding early buyers and stabilizing the price over time.

## Features

- **Exponential Bonding Curve**: Price increases exponentially as more tokens are bought, ensuring an efficient and dynamic pricing model.
- **Auto Liquidity**: Liquidity is automatically provided to the pool as the token sale progresses.
- **Fair Launch Mechanism**: Token price is determined by the bonding curve, ensuring fairness for all participants.
- **Transparent Token Issuance**: Token issuance is handled by the smart contract, ensuring transparency and trust.

## Learn More

To learn more about the Bonding Curve Contract and how to integrate it into your project, please refer to the following resources:
- [Bonding Curve Contract Documentation](https://github.com/DAOBase-AI/dao-pop-contracts/new/main/Buzzing-Curve-Contract/V2/README.md)

## Contract Deployment Process

### 1. Install Prerequisites

Before deploying the contract, you need to install the necessary tools.

#### Install **Node.js** and **npm** (Node Package Manager)

- **Node.js** is required to run Hardhat and install dependencies. You can download it from [nodejs.org](https://nodejs.org/).
- Once Node.js is installed, **npm** (which comes with Node.js) will allow you to install the necessary dependencies.

To check if Node.js and npm are installed correctly, run:
```bash
node -v
npm -v
```

#### Install **Hardhat**

Hardhat is a development environment to compile, deploy, test, and debug your Ethereum software. To install it, you first need to initialize a new npm project and then install Hardhat:

```bash
# Initialize a new npm project
npm init -y

# Install Hardhat and other dependencies
npm install --save-dev hardhat @nomiclabs/hardhat-ethers ethers
```

### 2. Clone the Repository

Clone the repository and navigate to the project folder:

```bash
git clone https://github.com/DAOBase-AI/dao-pop-contracts.git
cd dao-pop-contracts/Buzzing-Curve-Contract/V2
```

### 3. Install Dependencies

Run the following command to install all the required npm packages:

```bash
npm install
```

### 4. Configure the Environment

Create a `.env` file in the root directory of the project and add the necessary environment variables. This file will store your private keys and other sensitive data.

Example `.env` file:

```plaintext
DEPLOYER_PRIVATE_KEY=your_private_key_here
INFURA_PROJECT_ID=your_infura_project_id_here
```

Make sure to replace `your_private_key_here` with your Ethereum private key (the key that will be used to deploy the contract) and `your_infura_project_id_here` with your Infura project ID if you're using Infura for network access.

### 5. Compile the Contracts

Once you've installed the necessary dependencies and configured the environment, compile the smart contracts:

```bash
npx hardhat compile
```

### 6. Deploy the Contract

You can deploy the contract to your desired network (e.g., Rinkeby or Ethereum mainnet) by running the following command:

```bash
npx hardhat run --network your-network scripts/deploy.ts
```

Make sure to replace `your-network` with the name of the network you want to deploy to (e.g., `rinkeby`, `mainnet`, etc.).

### 7. Verify the Contract

Optionally, you can verify your contract on Etherscan using the following command:

```bash
npx hardhat verify --network your-network [CONTRACT_ADDRESS]
```

Replace `[CONTRACT_ADDRESS]` with the actual address of the deployed contract.
