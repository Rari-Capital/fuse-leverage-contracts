pragma solidity >=0.8.0;

// minimal interface for 
interface IExactOutputRouter {
    function initSwap(bytes calldata data) external;
}