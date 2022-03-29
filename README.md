# fuse-leverage-contracts
rough draft of cloneable univ3 swap receiver for openeing, closing, and editing single pair leveraged positions for multiple fuse pools




## Design Philisophy / Disclaimer 
`Smart Wallet / Leverage Manager (V1) is designed to be as simple as possible. This means that all computation and checks are done while building the transaction off-chain. If you decide to build your txns and monitor the positions opened by these contracts yourself, you are fully responsible for the proper execution. There may be unexpected effects in transacting with tokens permissionlessly added to uniswap and fuse(think thorchain debacle). The ability for liquidators to seize your collateral, just like with vanilla fuse, are at the mercy of factors out of the scope of these contracts such as oracles, twaps, or other dependencies.`

### Examples of unsafe assumptions to make without checking offchain:
1) univ3 pool assets 0/1 correctly coorespond to cToken 0/1
   - can be mixed up and ruin the entire txn if not checked for
2) the previous pool position is closed before opening a new one
   - can mess up your collateral or worse a frontend/future txn builds
3) the proper amount of leverage is taken 
   - can have unexpectedly low/high liquidation price or instant liquidation

Final reminder these contracts are wrappers for the existing logic of fuse, just as it was your responsiblity when looping leverage, its yours to use the provided frontend calculations or build the txn yourself

## Arcitecture
*see architecture.md for a cool ascii diagram*

`Accounts(EOAs or contracts) can call makeClone of the LeverageManagerFactory to clone an instance of the Smart Wallet (Leverage Manager / Account Data) contracts, in which the initialization function, mimicing a constructor, sets the account to the owner of the Smart Wallet.`

`Upon cloning a Smart Wallet, an Account can now transfer ERC20 tokens to it as margin, open/edit/close one lend/borrow leveraged position per pool, and withdraw their margin.`





