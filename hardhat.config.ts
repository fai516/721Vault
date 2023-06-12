import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 1000,
      },
    },
  },
  networks: {
    // Mainnet
    ETH_MAINNET: {
      url: "",
      accounts: [],
    },
    // Testnet
    ETH_TESTNET: {
      // Goerli
      url: "",
      accounts: [
        "",
      ],
    },
    // Local node
    hardhat: {
      mining: {
        auto: true,
        interval: 5000,
      },
    },
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD",
  },
  etherscan: {
    apiKey: {
      goerli: "",
      mainnet: "",
    },
  },
};

export default config;
