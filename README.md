## To deploy

> $ forge create --rpc-url https://polygon-mumbai.blockpi.network/v1/rpc/13c5d21c24d2294c5d27ba45c3e63d92b038036d --private-key <private_key> src/Sponsorship.sol:Sponsorship --etherscan-api-key <API_KEY_ETHERSCAN> --verify --constructor-args <USDT_TOKEN_ADDRESS> <FEE_RECEIVER_ADDRESS>

Abstract the function that will return true if user can accept reject offer

## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
