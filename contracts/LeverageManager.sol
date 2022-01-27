// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >= 0.7.6;
pragma abicoder v2;

import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3FlashCallback.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import "@uniswap/v3-core/contracts/libraries/LowGasSafeMath.sol";
import "@uniswap/v3-core/contracts/UniswapV3Pool.sol";

import "@uniswap/v3-periphery/contracts/base/PeripheryPayments.sol";
import "@uniswap/v3-periphery/contracts/base/PeripheryImmutableState.sol";
import "@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol";
import "@uniswap/v3-periphery/contracts/libraries/CallbackValidation.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/lens/QuoterV2.sol";

import "./interfaces/IERC20Minimal.sol";
import "./interfaces/IFTokenMinimal.sol";


// 

/// @title Flash contract implementation
/// @notice Important to note that there are not many guardrails in here
/// you are responsible for providing the right parameters if you decide to fork. 
contract LeverageManager is 
    IUniswapV3SwapCallback, 
    PeripheryImmutableState, 
    PeripheryPayments, 
    AccountData {
    using LowGasSafeMath for uint256;
    using LowGasSafeMath for int256;


    bool private iLock = false;

    ////////////  CONSTRUCTOR  ///////////

    function initialize(
        ISwapRouter _swapRouter,
        address _owner
    ) PeripheryImmutableState(this._factory, this._WETH9) external {
        require(!iLock);
        iLock = true;
        swapRouter = _swapRouter;
        owner = _owner;
    }


    // fee2 and fee3 are the two other fees associated with the two other pools of token0 and token1
    struct SwapCallbackData {
        address payer;
        uint256 millis;
        address token0;
        address token1;
        uint256 amount0;
        uint256 amount1;
        address fToken0;
        address fToken1;
        bool direction;
        PoolAddress.PoolKey poolKey;
    }

    ////////// FLASH CALLBACK //////////

    /// @param fee0 The fee from calling flash for token0
    /// @param fee1 The fee from calling flash for token1
    /// @param data The data needed in the callback passed
    /// @notice UNSAFE: Failure to ensure correctness of 
    /// parameters will lead to incoreect results
    /// @dev 
    function uniswapV3Callback(
        int256 _amount0,
        int256 _amount1,
        bytes calldata data
    ) external override {
        SwapCallbackData memory decoded = abi.decode(data, (SwapCallbackData));
        CallbackValidation.verifyCallback(factory, decoded.poolKey);
        bool dir = decoded.direction;


        // Rule #1: Borrow / Principle + Borrow <= Collateral Factor 
        // Rule #2: Hence CF determines max leverage: 1 / 1-CF 

        TransferHelper.safeApprove(decoded.token0, address(swapRouter), decoded.amount0);
        TransferHelper.safeApprove(decoded.token1, address(swapRouter), decoded.amount1);
        
        // Exact Amount in is the way to go, it may casue slight variation in opening leverage 
        
        IERC20Minimal token0 = IERC20Minimal(decoded.token0);
        IERC20Minimal token1 = IERC20Minimal(decoded.token1);  
        uint256 amountIn     = dir ? _amount0 : _amount1; 
        uint256 amountOut    = dir ? _amount1 : _amount0;
    
        IFTokenMinimal fIn  = dir ? 
        IFTokenMinimal(decoded.fToken0): 
        IFTokenMinimal(decoded.fToken1);

        IFTokenMinimal fOut = dir? 
        IFTokenMinimal(decoded.fToken1):
        IFTokenMinimal(decoded.fToken0);

        // TODO: ftoken methods
        bool opened; 
        if(dir) {
            bool opened = fIn.balanceOf(address(this)) == 0 ? true : false;
            fIn.mint(amountIn);
            fOut.borrow(amountOut);
            token1.transfer(msg.sender, amountOut);
            if(opened) {
                emit PositionOpened(

                );
            } else {
                emit PositionIncreased(

                );
            }
            
        } else {
            fIn.repayBorrow(amountIn);
            fOut.redeemUnderlying(amountOut);
            token0.transfer(msg.sender, amountOut);
            // transfer 
            if(fIn.borrowBalance() == 0) {
                emit PositionClosed(

                );
            } else {
                emit PositionDecreased(

                );
            }
        }   
        
        
    }


    /**
    * @dev: 0 and 1 represent lend and borrow of fuse pool respectively
    */
    struct SwapParams {
        address token0;
        address token1;
        address fToken0;
        address fToken1;
        uint24 fee;
        uint256 amount0;
        uint256 amount1;
        bool direction;
        uint160 sqrtPriceLimitX96;
        uint256 millis;
    }
    ///////// EOA CALLED FUNCTIONS ///////////

    /** 
    * @param params The parameters necessary for swap and fuse logic
    * @notice Calls the pools swap function with data needed in `uniswapV3Callback`
    * 
    * @param:
     */
    function initSwapUnsafe(SwapParams memory params) external OnlyOwner {
        
        PoolAddress.PoolKey memory poolKey =
            PoolAddress.PoolKey({token0: params.token0, token1: params.token1, fee: params.fee});
        IUniswapV3Pool pool = IUniswapV3Pool(PoolAddress.computeAddress(factory, poolKey));

        if(params.direction) {
            IERC20Minimal(params.token0).approve(address(this), params.amount0);
        }

        int256 amount = params.direction ? int256(-params.amount0) : params.amount0; // TODO: reconsider

        // See UniswapV3Pool.sol for specifications
        pool.swap(
            address.this,
            params.direction,
            amount, 
            params.sqrtPriceLimitX96,
            abi.encode(SwapCallbackData({
                payer:     msg.sender,
                millis:    200,
                token0:    params.token0,
                token1:    params.token1,
                amount0:   params.amount0,
                amount1:   params.amount1,
                fToken0:   params.fToken0,
                fToken1:   params.fToken1,
                poolKey:   poolKey,
                direction: params.direction
                })
            )
        );
    }


    function deposit(address _token, uint256 amount) external OnlyOwner {
        IERC20Minimal token = IERC20Minimal(_token);

        
    }

    function withdraw() external OnlyOwner {

    }


}
