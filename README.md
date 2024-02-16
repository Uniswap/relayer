# Relayer
Contracts that allow for the relaying of transactions to the UniversalRouter in exchange for ERC20 tokens. The contract ensures that UniversalRouter is called with the calldata encoded in the order and transfers tokens from the swapper to a specified recipient.

## RelayOrderReactor
The RelayOrderReactor is responsible for validating RelayOrders, transferring input tokens and making the requested onchain call to the Universal Router. There is no additional verification performed after an order is filled, so it is crucial to encode any desired checks for balance or ownership into the calldata within the order.

This contract does _not_ inherit the standard `IReactor` interface in UniswapX as the contract does not perform a callback to a filler. Fillers can execute orders by calling `execute(SignedOrder calldata order, address feeRecipient)` directly, passing in an order and the address which the order's fee should be sent to. For convenience, `execute(SignedOrder calldata order)` can also be called without the feeRecipient argument to direct all fees to the caller. Batch executes and permit + execute are enabled via built in multicall.

## RelayOrder
Swappers generate Relay Orders to be submitted onchain. These orders have one static input, one dynamic fee, and calldata encoded for the UniversalRouter.

The Input in a RelayOrder is a static amount which is sent to a specific recipient signed by the swapper. For example, an Input could be sent to the UniversalRouter to perform a relayed swap.

The fee specified in a RelayOrder is sent directly to `feeRecipient` and can optionally increase in value linearly over the lifetime of the order. The actual amount transferred will be resolved at the time of filling.

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