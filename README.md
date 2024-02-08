# Relayer
Contracts that allow for the relaying of transactions to the Universal Router in exchange for ERC20 payments. The contract ensures that any encoded onchain actions are executed successfully and transfers tokens from the swapper to any recipients.

## RelayOrderReactor
The RelayOrderReactor is responsible for validating RelayOrders, transferring input tokens and making any requested onchain calls. There is no additional verification performed after an order is filled, so it is crucial to encode any desired checks for balance or ownership into the order itself.

This contract does _not_ inherit the standard `IReactor` interface in UniswapX as the contract does not perform a callback to a filler.

There is also support for native ERC2612 permits and multicalls.

## RelayOrder
Swappers generate Relay Orders to be submitted onchain. These orders usually contain two inputs and calldata for a swap. 

Inputs for RelayOrders can optionally increase in value linearly over the lifetime of the order. The actual amount transferred will be resolved at the time of filling.

An input with a recipient field equal to the zero address is treated as a _tip_ which will be sent to the filler of the order.

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