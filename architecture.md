// TODO: add ascii diagram


## Spec 

### 1 Wallet Creation 
a. Smart leverage wallets can be initialized for an address by calling `makeClone()`. 

b. To get the current wallet of an address, call `ownerOfManager(address)`. 

c. This system is non upgradeable. This version of fuse margin accounts will always be accesible on the contract level by smart wallet owners.


### 2 Wallet Interaction (inherited by LeverageManager.sol)
a. Smart wallets contain fns for easy approval to spend principle in the fuse and uniswap systems, safe withdrawl of principle, and a convenience balanceOf fn.

b. Each fuse pool can have 1 position open at once, smart wallet contains a mapping of pool comptroller address to position state

### 3 Wallet Positions
Positions are interacted with and managed by the leverage manager contract. The initSwapUnsafe() fn is called by the frontend or directly to open, close, increase, or decrease leveraged positions of lend against borrow assets in fuse pools. A transaction goes as follows:

1. An asset into fuse is an asset out of uniswap pools and vice versa. initSwapUnsafe() is called with the SwapCallbackData payload containing all the information the contracts need.

2. An exact output swap is called on the first uni v3 pool in the path of swaps, the exact amount of the first asset requested is transferred out of uniswap, to be entered into fuse either as collateral or to repay a borrow to unlock collateral. 

3. The pool calls `uniV3SwapCallback()` of this contract. 
   
    a. If the path is a single hop ( 1 pool). We can go straight to `editPositionInternal()`

    b. Else the path is a multihop across > 1 pools, the external(\*1) `ExactOutputRouter` contract is called with the current payload to go down the path of pools, exact output swapping the minimum input required + fee of pool N from pool N + 1 to tranfer back to pool N, completing the previous swap. The data payload contains a field for the previous pool's minimum, fee, and address. This continues until the callback from last pool, where ExactOutputRouter instead safely(\*2) enters the leverage manager's `safeEditPositionFromRouter()` with the minimum required last asset in. This safely calls the Leverage Manager's `editPositionInternal()`

4. `editPositionInternal()` is called, which interacts with fuse by either:

    a. minting uniswaps output as collateral in addition to the user's specified margin (this makes up leverage), then borrowing and transferring to the last pool in the path uniswap's minimum asset in.
     - todo: determine if open positions of other assets revert here due to storage conflict and liquidation complication, or levy data interpretation of events and liquidation price entirely on the sender @jet 

    b. repaying the borrow with uniswaps exact output, and redeeming . 

     - if the repay is the borrow balance (close) then all collateral is redeemed to the smart wallet, and the user can withdraw their margin, or use it in another posiiton or pool 
     - otherwise, only the collateral reqired as input to uniswap is redeemed, which should scale proportionally with repay size before fees and slippage


