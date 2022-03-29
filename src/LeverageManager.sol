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
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/lens/QuoterV2.sol";

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
    using LowGasSafeMath for uint256;
    using LowGasSafeMath for int256;


    /*///////////////////////////////////////////////////////////////
                              "CONSTRUCTOR"
    //////////////////////////////////////////////////////////////*/

    bool private iLock = false;

    function initialize(
        ISwapRouter _swapRouter,
        address _owner
    ) virtual PeripheryImmutableState(this._factory, this._WETH9) external {
        require(!iLock);
        iLock = true;
        swapRouter = _swapRouter;
        owner = _owner;
    }


    // fee2 and fee3 are the two other fees associated with the two other pools of token0 and token1
    struct SwapCallbackData {
        address payer;    // todo: remove? 
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
        PoolAddress.PoolKey poolKey; 
    }

    ////////// FLASH CALLBACK //////////

    function uniswapV3Callback(
        int256 _amount0,    // 
        int256 _amount1,    // 
        bytes calldata data // 
    ) external override {
        SwapCallbackData memory decoded = abi.decode(data, (SwapCallbackData));
        // Validates call is from uniswap pool 
        CallbackValidation.verifyCallback(factory, decoded.poolKey);

        bool dir = decoded.direction;

        // The borrow asset of the pool should always be exact, 
        // weather its the output(lev up), or vice versa 
        (uint256 amountIn , uint256 amountOut) = dir ? 
        (_amount0, uint256(-_amount1)):
        (uint256(-_amount1), _amount0);
    
        (IFTokenMinimal fIn , IFTokenMinimal fOut ) = dir ? 
        (IFTokenMinimal(decoded.fToken0), IFTokenMinimal(decoded.fToken1)):
        (IFTokenMinimal(decoded.fToken1), IFTokenMinimal(decoded.fToken0)); 


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


    /**
    * @dev: 0 and 1 represent lend and borrow of fuse pool respectively
    */
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
