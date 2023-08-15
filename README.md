## This decentralized leverage trading dapp

Frontend can be found [here](ttps://github.com/IzuMan0x/decentralized-leveraged-trading-frontend)

## Proposed design is as follows

1. Mapping of user to trade pair to an array of position details
   1. position details
      1. amount
      2. long or short
      3. leverage
      4. position open time
2. if it is a limit order... not sure. Maybe use chainlink automation, but make sure the trade fees cover the cost to use chainlink. Then we can write the details to the position array.
3. Market order we can write the position straight to the array
4. User can close their position any time
5. Chainlink or bots can force close positions if price is met or time\*fees liquidate them.

\*\*difficulty is calculating how fees (static and dynamic) will affect the users position.
gains.trade fees are added everyhour. Maybe use chainlink or your own bot to call the contract and update fees...
