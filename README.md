# fuse-leverage-contracts
rough draft of cloneable univ3 swap receiver for openeing, closing, and editing single pair leveraged positions for multiple fuse pools




## Design Philisophy / Disclaimer 
`Smart Wallet / Leverage Manager (V1) is designed to be as simple as possible. This means that all computation and checks are done while building the transaction off-chain. If you decide to build your txns and monitor the positions opened by these contracts yourself, you are fully responsible for the proper execution. There may be unexpected effects in transacting with tokens permissionlessly added to uniswap and fuse(think thorchain debacle). The ability for liquidators to seize your collateral, just like with vanilla fuse, are at the mercy of factors out of the scope of these contracts such as oracles, twaps, or other dependencies.`


## Arcitecture
*see architecture.md for a cool ascii diagram*

`Accounts(EOAs or contracts) can call makeClone of the LeverageManagerFactory to clone an instance of the Smart Wallet (Leverage Manager / Account Data) contracts, in which the initialization function, mimicing a constructor, sets the account to the owner of the Smart Wallet. 

Upon cloning a Smart Wallet, an Account can now transfer ERC20 tokens to it as margin, open/edit/close one lend/borrow leveraged position per pool (^2a-b), and withdraw their margin.`

^2a: there is no chcek for max leveraage hit. mathematical limit is $$ \frac{1}{1 - collateralFactor}) $$ 
^2b: todo: is it safe to hard-code the position being closed upon borrow being 0? should this be the check?



