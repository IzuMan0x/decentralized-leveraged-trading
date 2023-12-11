## This decentralized leverage trading dapp

Live deployment of this smart contract with a front-end can be found here at [bettertrade.me](bettertrade.me)

Github for the front-end can be found [here](https://github.com/IzuMan0x/decentralized-leveraged-trading-frontend)

## This is trading Dapp inspired by gains.trade

## How to deploy OrderBook

System requirements:

1.  Please have Foundry installed with forge and anvil installed as well.

# Deployment Steps

1.  Download this repository and open a terminal inside the main directory.
1.  Run the following commands in the terminal.
    1. For local deployment:
       1. `anvil`
       2. `forge script script/DeployOrderBookForTests.s.sol:DeployOrderBookForTests --rpc-url http://127.0.0.1:8545 --broadcast`
       3. If this does not work check the RPC URL of the local blockchain (the one you deployed with the 'anvil' command) and change it accordingly. The above value is the default URL.
1.  For main-net of test-net (currently setup to deploy to sepolia):
    1.  Create an **.env** file that contains PRIVATE_KEY and ETHERSCAN_API_KEY. Use those exact names. Also, see **env.example**
    2.  `forge script script/DeployOrderBook.s.sol:DeployOrderBook --rpc-url "Paste your alchemy rpc URL Here" --broadcast`
    3.  Verifying the contract with etherscan.
        1.  `forge verify-contract --watch --chain-id 11155111 --compiler-version "v0.8.19+commit.7dd6d404" --constructor-args-path constructor-args.txt "paste the contract address here" src/OrderBook.sol:OrderBook`
            1.  In the above command the `--constructor-args-path constructor-args.txt` the constructor args must be defined at `/constructor-args.txt` with the args you used to deploy the contract.

## Running tests

1. Open a terminal in the root directory and run `forge test` (least info) or `forge test -vvvv` (most info) which will run all the tests.
2. To run a specific test use the following command `forge test --match-test replaceThisWithTestName -vvv  `
   1. The v's at the end represent the amount of information displayed in the terminal with nothing bein being the least and -vvvv being the most information.

## How to deploy MyUsdc

1. Just follow the above steps for deploying OrderBook and replace it with MyUsdc accordingly.
   1. Note: MyUsdc is a ERC20 token used for only for testing purposes. It has mint function that can be called by anyone.

## ❓Any questions of Feedback checkout the Discord channel here

[Discord](https://discord.com/invite/ra4gsDKy7Z)
