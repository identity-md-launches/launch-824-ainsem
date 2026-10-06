# Vendored dependencies

These are ordinary source files, with no submodules or package-install step.

- OpenZeppelin Contracts **v5.1.0**, MIT: the five Solidity files in the ERC20 import closure and `LICENSE`, copied unchanged from [the tagged upstream source](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.1.0). Used by the production token.
- forge-std **v1.9.6**, MIT/Apache-2.0: the complete `src/` directory and both licenses, copied unchanged from [the tagged upstream source](https://github.com/foundry-rs/forge-std/tree/v1.9.6). Used only by tests.

`SHA256SUMS` records the bytes as downloaded. From the project root, run `sha256sum -c lib/SHA256SUMS` to verify them. Tests and builds do not download dependencies. Foundry and the pinned Solidity compiler are execution tools supplied by the verification environment, not vendored dependencies.
