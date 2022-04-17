pragma solidity 0.8.11;

import "./LeverageManagerFactory.sol";

contract ExactOutputRouter {

    
    LeverageManagerFactory immutable factory;

    constructor(address _factory) {
        factory = LeverageManagerFactory(_factory);
    }

   // todo: just make this and params the same lol
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
        uint256 hopNum; // increments 
        address paybackHop;
        uint24  paybackFee;
        uint160 sqrtPriceLimitX96;
        bytes path;
        PoolAddress.PoolKey poolKey; 
    }


    function uniswapV3SwapCallback(
        int256 _amount0,
        int256 _amount1,
        bytes calldata data
    ) external {
        require(_amount0 > 0 || _amount1 > 0); // swaps entirely within 0-liquidity regions are not supported
        SwapCallbackData memory data = abi.decode(_data, (SwapCallbackData));

        if(data.path.hasMultiplePools()) {
            // 
        } else {
            // last asset hit, call 
        }
    }

    function initSwap(

        bytes calldata data
    ) external {
        
        // prevents positions being maliciously managed by third parties on behalf of a manager
        require(factory.approvedManager(msg.sender));

    }

    function exactOutputInternal() internal {
        // move redundant exact output logic here potentially
    }

    
}