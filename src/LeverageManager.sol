// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >= 0.7.6;
pragma abicoder v2;


import "./LevSmartWallet.sol";
import "@uniswap/v3-periphery/contracts/base/PeripheryPayments.sol";
import "@uniswap/v3-periphery/contracts/base/PeripheryImmutableState.sol";
import "@uniswap/v3-periphery/contracts/lens/QuoterV2.sol";


// Interfaces
import "./interfaces/IExactOutputRouter.sol";
import "./interfaces/IERC20Minimal.sol";
import "./interfaces/IFTokenMinimal.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";


// Libraries
import "./libraries/ERC20Helper.sol";
import "@uniswap/v3-core/contracts/libraries/LowGasSafeMath.sol";
import "@uniswap/v3-periphery/contracts/libraries/Path.sol";
import "@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol";
import "@uniswap/v3-periphery/contracts/libraries/CallbackValidation.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";


/// @title Flash contract implementation
contract LeverageManager is 
    IUniswapV3SwapCallback, 
    PeripheryImmutableState, 
    PeripheryPayments,
    LevSmartWallet {
    using LowGasSafeMath for uint256; // todo: depricate for 0.8
    using LowGasSafeMath for int256;  // todo: depricate for 0.8
    using Path for bytes;



    /*///////////////////////////////////////////////////////////////
                              "CONSTRUCTOR"
    //////////////////////////////////////////////////////////////*/


    // initializer lock
    bool private iLock = false;


    function initialize(
        address _owner
    ) virtual PeripheryImmutableState(this._factory, this._WETH9) external {
        require(!iLock);
        iLock = true;
        owner = _owner;
    }


    struct SwapCallbackData {
        // Fuse-relevant callback data:
        uint256 margin;     // Actual collateral deposited in fuse from smart wallet      
        uint256 orderSize;  // Either rest of principle for levering up, or full fuse repay amount
        address cTokenIn;   // cToken minted in / repaid to fuse pool, exact output of uniswap
        address cTokenOut;  // cToken borrowed out / redeemed from fuse pool, minimuim input of uniswap
        address fPool;      // key: Fuse Pool comptroller address, value: current pool Position struct 
        bool    direction;  // determines increasing or decreasing positiion todo: needed?

        // UniV3-relevant callback data:
        address paybackHop;
        uint24  paybackFee;
        uint256 paybackAmt;
        uint256 millis;   
        uint160 sqrtPriceLimitX96;
        bytes path;
        PoolAddress.PoolKey poolKey; 
    }


    // 
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
        int256 _paybackAmt = _amount0 > _amount1 ? -int256(_amount0) : -int256(_amount1);

        bytes path = decoded.path; 
        (address a, address b, uint24 poolFee) = path.decodeFirstPool();
        

        if(path.hasMultiplePools()) {

            // First hop does not have previous to payback 
            if(decoded.paybackAmt > 0) { 
                (bool success , ) = safeTransferFrom(
                    b, 
                    address(this), 
                    address(getPool(a, b, poolFee)), 
                    _paybackAmt
                );
                require(success); // todo: do we need this? it may revert regardless and we have max slippage
            } 
            
            decoded.path = path.skipToken();
            decoded.paybackAmt = _paybackAmt;

            (address b, address c, uint24 nextFee) = decoded.path.decodeFirstPool();
            bool zeroForOne = c < b;

            getPool(b, c, nextFee).swap(
                // todo: swap params
            );

      
        } else {
            editPositionInternal(
                _amount0,
                _amount1,
                decoded
            );
        }
 
    }


    
    function editPositionInternal(
        int256 _amount0,
        int256 _amount1,
        SwapCallbackData memory data
        ) internal {
        
        int256 _paybackAmt = _amount0 > _amount1 ? -int256(_amount0) : -int256(_amount1);

        IFTokenMinimal fIn  = IFTokenMinimal(data.cTokenIn);
        IFTokenMinimal fOut = IFTokenMinimal(data.cTokenOut);

        if(data.margin > 0) { 
            if(fIn.balanceOf(address(this)) == 0) { 
                // open case
               
                if (positions[data.fPool].isOpen) revert(); // todo: build msg

                positions[data.fPool].isOpen = true;
                emit PositionOpened();
            
            } else { 
                // increase case 
                emit PositionIncreased();
            }

            // Mint lend asset and receive borrow asset
            fIn.mint(amountIn+data.margin); // todo: amountIn plus margin amount
            fOut.borrow(amountOut);
           
        } else {
            // Payback borrow asset and receive lend asset
            fIn.repayBorrow(amountIn);
            fOut.redeemUnderlying(amountOut);

            if(fIn.borrowBalanceCurrent(address(this)) == 0) {
                // close case
                // removes all underlying to close the position fully
                fOut.redeemUnderlying(fOut.balanceOf(address(this)));

                positions[data.fPool].isOpen = false;
                emit PositionClosed();

            // decrease case 
            } else {
                emit PositionDecreased();
            }
        }   

        // payback the flash swap with received asset from fuse

        (bool success , ) = safeTransferFrom(
                    a, 
                    address(this), 
                    address(getPool(data.paybackHop, a, data.paybackFee)), 
                    _paybackAmt
                );   
        
    }




    ///////// OWNER FUNCTIONS ///////////

   /**
    * 
    * 
    */
    function initSwapUnsafe(SwapParams memory params) external OnlyOwner {
        PoolAddress.PoolKey memory poolKey = PoolAddress.PoolKey(
                {token0: params.token0, token1: params.token1, fee: params.fee}
        );

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


   function positionManualOverride(address pool) {
       // todo: implement override than can set a position to closed
   }


}
