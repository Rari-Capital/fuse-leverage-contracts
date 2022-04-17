// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >= 0.7.6;
pragma abicoder v2;

import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3FlashCallback.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import "@uniswap/v3-core/contracts/libraries/LowGasSafeMath.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import "@uniswap/v3-periphery/contracts/base/PeripheryPayments.sol";
import "@uniswap/v3-periphery/contracts/base/PeripheryImmutableState.sol";
import "@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol";
import "@uniswap/v3-periphery/contracts/libraries/CallbackValidation.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-periphery/contracts/lens/QuoterV2.sol";
import "@uniswap/v3-periphery/contracts/libraries/Path.sol";

// Interfaces
import "./interfaces/IExactOutputRouter.sol";
import "./interfaces/IERC20Minimal.sol";
import "./interfaces/IFTokenMinimal.sol";

import "./LevSmartWallet.sol";


// 

/// @title Flash contract implementation
/// @notice Important to note that there are not many guardrails in here
/// you are responsible for providing the right parameters if you decide to fork. 
contract LeverageManager is 
    IUniswapV3SwapCallback, 
    PeripheryImmutableState, 
    PeripheryPayments,
    LevSmartWallet {
    using LowGasSafeMath for uint256; // todo: depricate for 0.8
    using LowGasSafeMath for int256;  // todo: depricate for 0.8
    using Path for bytes;

    /*///////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    // initializer lock
    bool private iLock = false;

    IExactOutputRouter router;

    /*///////////////////////////////////////////////////////////////
                              "CONSTRUCTOR"
    //////////////////////////////////////////////////////////////*/



    function initialize(
        address _owner,
        address _router
    ) virtual PeripheryImmutableState(this._factory, this._WETH9) external {
        require(!iLock);
        iLock = true;
        owner = _owner;
        router = IExactOutputRouter(_router);
        blockPosted = block.number;
    }


    struct SwapCallbackData {
        uint256 millis;   
        uint256 margin;
        address token0;   // underlying lend token
        address token1;   // underlying borrow token 
        uint256 amount0;  // ?exact amount in (lev up) or out (lev down)
        uint256 amount1;  // ?vice versa
        address fToken0;  // lend cToken
        address fToken1;  // borrow ctoken
        address fPool;
        bool    direction;  // determines increasing or decreasing positiion todo: needed?
        uint256 hopNum; 
        address paybackHop;
        uint24  paybackFee;
        uint160 sqrtPriceLimitX96;
        bytes path;
        PoolAddress.PoolKey poolKey; 
    }


    ////////// FLASH CALLBACK //////////

    /**
    * Opens, closes, or edits leveraged isolated fuse pool positions of the smart wallet
    * by using uniswap optimistic swaps. Because in fuse we are always going from
    * one asset lend to one asset borrow (|| vice versa), we use swap instead of flash
    *
    * The callback will use the first and last asset in a single or multi hop swap
    * to alter fusev1 positions  
    */
    function uniswapV3SwapCallback(
        int256 _amount0,    // 
        int256 _amount1,    // 
        bytes calldata data // 
    ) external override {
        SwapCallbackData memory decoded = abi.decode(data, (SwapCallbackData));
        // Validates call is from uniswap pool 
        CallbackValidation.verifyCallback(factory, decoded.poolKey);

        bool dir = decoded.direction;

        // the amount to payback the exact output swap
        int256 paybackAmt = _amount0 > _amount1 ? -int256(_amount0) : -int256(_amount1);

        (address a, address b, uint24 fee) = path.decodeFirstPool();
        

        if(path.hasMultiplePools()) {

            // elegant way to pay back the previous pool in the multihop
            IERC20Minimal(a).transfer(
                address(getPool(decoded.paybackHop, a, decoded.paybackFee)),
                paybackAmt
            );
            
            // reset payback data to the current pair to swap
            decoded.paybackHop = a;
            decoded.paybackFee = fee;
            
            decoded.path = path.skipToken;
            
            bool zeroForOne = b < a;

            router.initSwap(abi.encode(decoded));

      
        } else {
            editPositionInternal(decoded);
        }


        // The borrow asset of the pool should always be exact, 
        // weather its the output(lev up), or vice versa 
        (uint256 amountIn , uint256 amountOut) = dir ? 
        (_amount0, uint256(-_amount1)):
        (uint256(-_amount1), _amount0);
    
        (IFTokenMinimal fIn , IFTokenMinimal fOut ) = dir ? 
        (IFTokenMinimal(decoded.fToken0), IFTokenMinimal(decoded.fToken1)):
        (IFTokenMinimal(decoded.fToken1), IFTokenMinimal(decoded.fToken0)); 



        // todo: potentially move to seperate function, call conditionally either
        // before/after multihop or instantly for single hop

        if(dir) {
            // todo: test that dust is a ui issue and can be removed
            // open case
            if(fIn.balanceOf(address(this)) == 0) {
                // Only one asset can be longed at a time in a pool
                if (positions[decoded.fPool].isOpen) revert(); // todo: build msg

                positions[decoded.fPool].isOpen = true;
                emit PositionOpened();

            // increase case 
            } else {
                emit PositionIncreased();
            }

            // Mint lend asset and receive borrow asset
            fIn.mint(amountIn+decoded.margin); // todo: amountIn plus margin amount
            fOut.borrow(amountOut);
           
        } else {
            // Payback borrow asset and receive lend asset
            fIn.repayBorrow(amountIn);
            fOut.redeemUnderlying(amountOut);

            // close case
            if(fIn.borrowBalanceCurrent(address(this)) == 0) {
                // removes all underlying to close the position fully
                fOut.redeemUnderlying(fOut.balanceOf(address(this)));

                positions[decoded.fPool].isOpen = false;
                emit PositionClosed();

            // decrease case 
            } else {
                emit PositionDecreased();
            }
        }   

        // payback the flash swap with received asset from fuse
        address payback = dir ? decoded.token1 : decoded.token0;
        IERC20Minimal(payback).transfer(msg.sender, amountOut);  
    }

    // safety check 
    function editPositionFromRouter(bytes calldata data) external {
        require(msg.sender == address(router));
        SwapCallbackData decoded = abi.decode(data, (SwapCallbackData));
        editPositionInternal(decoded);
    }

    // 
    function editPositionInternal(SwapCallbackData memory data) internal {
        // todo: move logic after else statements of callback here
    }


    /**
    * @dev fork of univ3 router exact output 
    */
    function exactOutputInternal(
        uint256 amountOut,
        uint160 sqrtPriceLimitX96,
        SwapCallbackData memory data
    ) private returns (uint256 amountIn) {

        // path is sliced down every swap, first pool is always current pool in multihop
        (address tokenOut, address tokenIn, uint24 fee) = data.path.decodeFirstPool();
        
        bool dir = tokenIn < tokenOut;

        (int256 amount0Delta, int256 amount1Delta) =
            getPool(tokenIn, tokenOut, fee).swap(
                address(this),
                dir,
                -amountOut.toInt256(),
                sqrtPriceLimitX96 == 0
                    ? (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
                    : sqrtPriceLimitX96,
                abi.encode(data)
            );
    }
    
    struct SwapParams {
        address token0;
        address token1;
        address fToken0;
        address fToken1;
        address comptroller;
        uint24  fee;
        int256 amount;
        uint256 margin;
        bool direction;
        uint160 sqrtPriceLimitX96;
        uint256 millis;
    }


    ///////// EOA CALLED FUNCTIONS ///////////

    /** 
    * @param params The parameters necessary for swap and fuse logic
    * @dev checks for proper margin balacne and other parameters are not made,
    * sender / builder of txn responsible for proper call 
    * @notice Calls the pools swap function with data needed in `uniswapV3Callback`
    * 
    * @param:
     */
    function initSwapUnsafe(SwapParams memory params) external OnlyOwner {
        PoolAddress.PoolKey memory poolKey =
            PoolAddress.PoolKey({token0: params.token0, token1: params.token1, fee: params.fee});
        IUniswapV3Pool pool = IUniswapV3Pool(PoolAddress.computeAddress(factory, poolKey));


        // See UniswapV3Pool.sol for specifications
        pool.swap(
            address.this,
            params.direction,
            params.amount, 
            params.sqrtPriceLimitX96,
            abi.encode(SwapCallbackData({
                payer:     msg.sender,
                millis:    200,
                token0:    params.token0,
                token1:    params.token1,
                fToken0:   params.fToken0,
                fToken1:   params.fToken1,
                poolKey:   poolKey,
                fPool:     params.comptroller,
                direction: params.direction
                })
            )
        );
    }

   


}
