.PHONY: dependencies wormhole_dependencies

all: build

.PHONY: dependencies
dependencies: forge_dependencies wormhole_dependencies

.PHONY: forge_dependencies
forge_dependencies: lib/forge-std

lib/forge-std:
	forge install foundry-rs/forge-std --no-git

.PHONY: wormhole_dependencies
wormhole_dependencies: wormhole/ethereum/build

wormhole/ethereum/build:
	git clone --depth 1 --branch dev.v2 --single-branch https://github.com/certusone/wormhole.git
#	cd wormhole/ethereum && npm ci && npm run build && make .env
