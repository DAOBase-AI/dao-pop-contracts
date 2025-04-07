
# Fundraising Model Contract

The Fundraising Model Contract is a smart contract designed to facilitate token sales with built-in treasury support and liquidity pool (LP) creation. This contract enables creators to run fixed token sales while ensuring funds are managed securely and efficiently.

## Intro

The Fundraising Model Contract provides a comprehensive solution for fixed token sales with a transparent fundraising process. It includes treasury management features that allow creators to manage funds raised during the sale and automatic liquidity pool (LP) creation to ensure ongoing liquidity for token holders.

This contract is ideal for projects seeking to raise funds through token sales with clear and secure financial management.

## Features

- **Fixed Token Sale**: Conduct a fixed token sale, where tokens are sold at a fixed price.
- **Treasury Management**: Integrated treasury system to manage and store funds raised during the sale.
- **LP Creation**: Automatically create liquidity pools for token and ETH pairing.
- **Security**: Funds raised are securely stored in the treasury, and the smart contract ensures transparent distribution.
- **Fair Distribution**: The fundraising process is handled by the smart contract, ensuring a fair and equitable distribution of tokens.

## Learn More

For more details about the Fundraising Model Contract and its deployment, check out these resources:
- [Fundraising Model Contract Documentation](https://github.com/DAOBase-AI/dao-pop-contracts/new/main/Fundraising-Model-Contract/V1/README.md)

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

Clone this repository and navigate to the project directory:

```bash
git clone https://github.com/DAOBase-AI/dao-pop-contracts.git
cd dao-pop-contracts/Fundraising-Model-Contract
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
PRIVATE_KEY=your_private_key_here
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
