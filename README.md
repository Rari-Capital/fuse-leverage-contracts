# fuse-leverage-contracts
rough draft of cloneable univ3 swap receiver for openeing, closing, and editing single pair leveraged positions for multiple fuse pools



--- 
## Design Philisophy / Disclaimer 
`Smart Wallet / Leverage Manager (V1) is designed to be as simple as possible. This means that all computation and checks are done while building the transaction off-chain. If you decide to build your txns and monitor the positions opened by these contracts yourself, you are fully responsible for the proper execution. There may be unexpected effects in transacting with tokens permissionlessly added to uniswap and fuse(think thorchain debacle). The ability for liquidators to seize your collateral, just like with vanilla fuse, are at the mercy of factors out of the scope of these contracts such as oracles, twaps, or other dependencies.`

### Examples of unsafe assumptions to make without checking offchain:
1) univ3 pool assets 0/1 correctly coorespond to cToken 0/1
   - can be mixed up and ruin the entire txn if not checked for
2) these optimistic swaps are for majors/stables only
   - as of writing this, we haven't implemented univ3 flash() + router for more exotic pairs, its just a vanilla optimistic swap good for leverage against stables 
3) the previous pool position is closed before opening a new one
   - can mess up your collateral or worse a frontend/future txn builds
4) the proper amount of leverage is taken 
   - can have unexpectedly low/high liquidation price or instant liquidation

Final reminder these contracts are wrappers for the existing logic of fuse, just as it was your responsiblity when looping leverage, its yours to use the provided frontend calculations or build the txn yourself
---
## Arcitecture
*see architecture.md for a cool ascii diagram*

`Accounts(EOAs or contracts) can call makeClone of the LeverageManagerFactory to clone an instance of the Smart Wallet (Leverage Manager / Account Data) contracts, in which the initialization function, mimicing a constructor, sets the account to the owner of the Smart Wallet.`

`Upon cloning a Smart Wallet, an Account can now transfer ERC20 tokens to it as margin, open/edit/close one lend/borrow leveraged position per pool, and withdraw their margin.`

---
## Transaction Building 
` Transactions and checks are done off chain in the Fuse-Sdk. The functions within the Lev module are documented in progress below`
## Metadata Getters 
---
## getUserWallet
**js/ts**
~~~typescript
   async function getUserWallet(user: string) {}
~~~
**Params**
- `user` : Address of sender / owner of smart wallet
  
**Returns**
- `string address || undefined` : address of user's smart wallet, or undefined if user's wallet not deployed yet
  
---

## getCurrentPositions
**js/ts**
~~~typescript
async function getCurrentPositions(user: string) {}
~~~
**Params**
- `user` : string address of user to query positions of
   
**Returns**
- `Event[]` : List of ethers event types for each user position that the user hasn't closed yet 
  - *Doesn't check for position status like post liquidation or edit

---
## getPositionStatus
**js/ts**
~~~typescript 
async function getPositionStatus(
   position: Event, 
   wallet:   Contract
   ) {}
~~~
**Params**
- `position` : ethers event of the opened position to get status of
- `wallet` : todo this is the sender, this can be removed
  
**Returns**
- `Position` : A position object todo add this to module
---
## Position Math Overview and Getters 
### *Realized slippage approximation by order type*
|Flash Method|Liquid Pairs| Exotic Pairs |
|---|---|--|
|flash swap|low|high|
|flash loan|higher|lower|


```
So what's happening here? 

Liquid Swap (single hop):
If we have a liquid univ3 pair 0-1 that is the lend-borrow in fuse, we call a flash swap in the Smart Wallet. This transaction occurs as follows for upping leverage: the uni pool optimistically transfers the contract some amount of asset 0 to be collateralized, then the contract borrows the specific amount from fuse to repay the loan in asset 1. Because we want borrow amount in fuse to always be known, the inverse(lowering leverage) is receiving an exact amount of the borrow asset 1 to repay and redeeming some lend 0 to pay back univ3 swap.

As you can see, this is why with leverage positions across defi, the leverage changes slightly according to slippage the second the transaction completes.

Illiquid Swap (multi hop):
Eth <- USDC   USDC <- DAI   DAI <- Frax 
The contract recieves the exact out of the first pair, the required amount of the asset in for that pool is received as an exact output for the next pool in the chain of assets, until the last. The last required asset in is paid either by borrowing it or redeeming it, exact output being either cToken minted(collateralized) / repaid respectively. 
 ```
## getZeroForOne() {}
`Should be the first function called when dealing with the 2 specific tokens in a position. Uniswap 0 and 1 may be the opposite of fuse lend and borrow!`

--- 
## getPath
`Gets the univ3 router path between swapping 2 assets. The total slippage + gas fees should be compared between a single hop (typically cheaper for liquid majors) and a multi-hop (typically cheaper for illiquid pair trades) before deciding to call either flash swap or flash loan in the fuse leverage contracts`


---

## getBorrowSizeOut
`Given a certain lend size and path, this returns the exact asset 0 (that should be checked as same as fuse borrow underlying in getZeroForOne()) that is needed out `

---
## getLendSizeOut


## Setters 







