require("@nomicfoundation/hardhat-ethers");
require("@nomicfoundation/hardhat-chai-matchers");

/**
 * The Xelora contracts are pinned to Solidity 0.4.23, so the compiler is too.
 * `evmVersion` is pinned to byzantium because that is the network rule set
 * these contracts were written against.
 */
module.exports = {
  solidity: {
    version: "0.4.23",
    settings: {
      optimizer: { enabled: true, runs: 200 },
      evmVersion: "byzantium"
    }
  },
  networks: {
    hardhat: {
      // The contracts are compiled for byzantium, but the test network runs a
      // modern hardfork so that current tooling can submit transactions to it.
      allowUnlimitedContractSize: false
    }
  }
};
