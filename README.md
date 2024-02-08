# Relayer
Contracts that allow for the relaying of transactions to the Universal Router. Swappers generate orders that offer some amount of an ERC20 token as long as the encoded calldata is executed onchain.

# Integrating as a filler

# Deployment Addresses

# Usage

```
# install dependencies
forge install

# compile contracts
forge build

# run unit tests
forge test

# setup hardhat
yarn && yarn presymlink && yarn symlink

# generate calldata for integration tests
yarn test

# setup .env
cp .env.example .env

# run integration tests
FOUNDRY_PROFILE=integration forge test
```

# Audit

# Bug Bounty