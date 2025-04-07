import "dotenv/config";
import {HardhatUserConfig} from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomiclabs/hardhat-solhint";
//import "@nomicfoundation/hardhat-verify";
import "hardhat-contract-sizer";
import "@openzeppelin/hardhat-upgrades";
import "hardhat-gas-reporter";




const config: HardhatUserConfig = {
    defaultNetwork: "hardhat",
    solidity: {
        compilers: [
            {
                version: "0.8.19",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 50,
                    },
                    viaIR: true,
                },
            },
            {
                version: "0.8.13",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 50,
                    },
                    viaIR: true,
                },
            },
            {
                version: "0.8.20",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 50,
                    },
                    viaIR: true,
                },
            },
            {
                version: "0.7.6",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 50,
                    },
                    viaIR: true,
                },
            },
        ],
        overrides: {
            "contracts/libraries/TickMath.sol": {
                version: "0.7.6",
                settings: {optimizer: {
                        enabled: true,
                        runs: 50,
                    },}
            },
        }
        
    },

    networks: {
      linea_goerli: {
        url: `https://rpc.goerli.linea.build/`,
        accounts: [`${process.env.PRIVATE_KEY}`],
      },
      linea_mainnet: {
        url: `https://rpc.linea.build/`,
        accounts: [`${process.env.PRIVATE_KEY}`],
        },
        sepolia: {
            url: `https://ethereum-sepolia.publicnode.com`,
            accounts: [`${process.env.PRIVATE_KEY}`],
        },
         mainnet: {
            url: `https://ethereum.publicnode.com`,
            accounts: [`${process.env.PRIVATE_KEY}`],
        },
        arbitrum: {
            url: `https://arb-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_ARB_ONLINE}`,
            accounts: [`${process.env.PRIVATE_KEY}`],
        },
        arbitrumGoerli: {
            url: `https://arb-goerli.g.alchemy.com/v2/${process.env.ALCHEMY_ARB_GOERLI}`,
            accounts: [`${process.env.PRIVATE_KEY}`],
        },

    "base-mainnet": {
        url: 'https://mainnet.base.org',
        accounts:  [`${process.env.PRIVATE_KEY}`],
    },
    "base-goerli": {
        url: "https://goerli.base.org",
        accounts:  [`${process.env.PRIVATE_KEY}`],
    },
    "base-sepolia": {
        url: "https://sepolia.base.org",
        accounts:  [`${process.env.PRIVATE_KEY}`],
    },

    },
    etherscan: {
        apiKey: {
            mainnet: `${process.env.API_KEY_ETH_ONLINE}`,
            sepolia: `${process.env.API_KEY_ETH_GOERLI}`,
            arbitrumOne: `${process.env.API_KEY_ARB_ONLINE}`,
            arbitrumGoerli: `${process.env.API_KEY_ARB_GOERLI}`,
            "base-goerli": `${process.env.API_KEY_BASE_ONLINE}`,
            "base-sepolia": `${process.env.API_KEY_BASE_ONLINE}`,
            "base-mainnet": `${process.env.API_KEY_BASE_ONLINE}`,
            linea_mainnet: `${process.env.API_KEY_LINEA_ONLINE}`,
            linea_goerli: `${process.env.API_KEY_LINEA_GOERLI}`            
            
        },
        customChains: [
            {
                network: "base-mainnet",
                chainId: 8453,
                urls: {
                 apiURL: "https://api.basescan.org/api",
                 browserURL: "https://basescan.org"
                }
              },
            {
                network: "base-goerli",
                chainId: 84531,
                urls: {
                    apiURL: "https://api-goerli.basescan.org/api",
                    browserURL: "https://goerli.basescan.org",
                },
            },
            {
                network: "base-sepolia",
                chainId: 84532,
                urls: {
                    apiURL: "https://api-sepolia.basescan.org/api",
                    browserURL: "https://sepolia.basescan.org",
                },
            },
            {
                network: "arbitrumGoerli",
                chainId: 421613,
                urls: {
                    apiURL: "https://api-goerli.arbiscan.io/api",
                    browserURL: "https://goerli.arbiscan.io/",
                },
            },
            {
                network: "arbitrumOne",
                chainId: 42161,
                urls: {
                    apiURL: "https://api.arbiscan.io/api",
                    browserURL: "https://arbiscan.io/",
                },
            },
            {
                network: "linea_mainnet",
                chainId: 59144,
                urls: {
                    apiURL: "https://api.lineascan.build/api",
                    browserURL: "https://lineascan.build/"
                  },
            },
            {
                network: "linea_goerli",
                chainId: 59140,
                urls: {
                    apiURL: "https://api-testnet.lineascan.build/api",
                    browserURL: "https://goerli.lineascan.build/address",
                },
            },
            
        ],
    },
    gasReporter: {
        enabled: `${process.env.REPORT_SIZE}` == "true",
        currency: 'USD',  
        gasPrice: 21      
    },
    contractSizer: {
        runOnCompile: `${process.env.REPORT_SIZE}` == "true",
    },
};

export default config;