include testing.env

.PHONY: dependencies unit-test forge-test integration-test clean all

all: build

.PHONY: clean
clean:
	rm -rf anvil.log node_modules lib out

.PHONY: dependencies
dependencies: node_modules lib/forge-std

node_modules:
	yarn

lib/forge-std:
	forge install foundry-rs/forge-std --no-git --no-commit

build: dependencies
	forge build --skip Test My WormholeSimulator .t.sol .s.sol

.PHONY: unit-test
unit-test: forge-test

.PHONY: forge-test
forge-test: dependencies
	forge test --fork-url ${TESTING_FORK_RPC_MUMBAI} -vv --via-ir
	rm -rf lib/forge-std/.git

.PHONY: forge-test-verbose
forge-test-verbose: dependencies
	forge test --fork-url ${TESTING_FORK_RPC_MUMBAI} -vvvvv --via-ir
	rm -rf lib/forge-std/.git

.PHONY: test
test: forge-test
