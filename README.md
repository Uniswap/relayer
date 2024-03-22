# Relayer
Contracts that allow for the relaying of transactions to the UniversalRouter in exchange for ERC20 tokens. The contract ensures that UniversalRouter is called with the calldata encoded in the order and transfers tokens from the swapper to a specified recipient.

## RelayOrderReactor
The RelayOrderReactor is responsible for validating RelayOrders, transferring input tokens and making the requested onchain call to the Universal Router. There is no additional verification performed after an order is filled, so it is crucial to encode any desired checks for balance or ownership into the calldata within the order.

This contract does _not_ inherit the standard `IReactor` interface in UniswapX as the contract does not perform a callback to a filler. The following functions are available for fillers to call:

- `execute(SignedOrder calldata order, address feeRecipient)`
- `execute(SignedOrder calldata order)` 
- `permit(ERC20 token, address owner, address spender, uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s)`
- `multicall(bytes[] calldata data)`

Execute must be called with an order and its signature. Providing a feeRecipient argument is optional and if omitted, fees will be sent to the caller.

With multicall any combination of the calls above can be batched allowing callers to fill multiple orders in a single call, or actions like permit + execute.

## RelayOrder
Swappers generate Relay Orders to be submitted onchain. These orders have one static input, one dynamic fee, and calldata encoded for the UniversalRouter.

The Input in a RelayOrder is a static amount which is sent to a specific recipient signed by the swapper. For example, an Input could be sent to the UniversalRouter to perform a relayed swap.

The fee specified in a RelayOrder is sent directly to `feeRecipient` and can optionally increase in value linearly over the lifetime of the order. The actual amount transferred will be resolved at the time of filling.

# Integrating as a filler

# Deploy Script 

forge script --broadcast \
--rpc-url <RPC_URL> \
--private-key <PRIV_KEY> \
--sig 'run(address)' \
DeployRelayOrderReactor \
<UNIVERSAL_ROUTER_ADDRESS> \
--etherscan-api-key <API_KEY> \
--verify

# Deployment Addresses

| Address           | Chain | UniversalRouter Address |
| :---------------- | :------: | ----: |
| [0x0000000000A4e21E2597DCac987455c48b12edBF](https://etherscan.io/address/0x0000000000A4e21E2597DCac987455c48b12edBF)    |   Mainnet   | [0x3fC91A3afd70395Cd496C647d5a6CC9D4B2b7FAD](https://etherscan.io/address/0x3fC91A3afd70395Cd496C647d5a6CC9D4B2b7FAD) |

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