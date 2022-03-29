pragma solidity >=0.7.6;

// import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import "./LeverageManager.sol";
import "./libraries/ERC20Helper.sol";

contract LevSmartWallet is ERC20Helper {

    
    address constant fee = 3000;
    address constant factory = address(""); // TODO: get address 
    address constant _WETH9 = address(""); // TODO: get address
    ISwapRouter constant swapRouter = ISwapRouter(""); // TODO: get address 


    address public owner;

    // comptroller => current position mapping 
    mapping(address => position) private positions;
    mapping(address => mapping(address => uint256)) public tokens;

    struct Position {
        address token0;
        address token1;
        address ftoken0;
        address fToken1;
        uint256 principle;
        uint256 loan;
        bool    isOpen; 
    }

    event MarignDeposit(address indexed token, uint256 amount);

    event MarginWithdraw(address indexed token, uint256 amount);

    event PositionOpened(
        address indexed pool, 
        address token0, 
        address token1, 
        uint256 principle, 
        uint256 loan
    );

    event PositionIncreased(
        address indexed pool,
        address token0,
        address token1,
        uint256 amount
    );
    
    event PositionDecreased(
        address indexed pool,
        address token0,
        address token1,
        uint256 amount
    );

    event PositionClosed(
        address indexed pool,
        address token0,
        address token1
    );

    modifier OnlyOwner {
        require(msg.sender == owner);
        _;
    }

    function getPosition(address pool) public returns (Position) {
        return positions[pool];
    }


    // todo: delete? 
    function chown(address _newOwner) external {
        require(msg.sender == owner);
        owner = _newOwner;
    }
    
    
      /*////////////////////////////////////////////////////////
     /                  ERC20 INTERACTIONS                    /
    ////////////////////////////////////////////////////////*/

    // @dev safe unsafe withdraw of margin to owners wallet
    function withdraw(address _token, uint256 amount) external OnlyOwner {
        safeTransferFrom(_token, address(this), msg.sender, amount);
        emit MarginWithdraw(_token, amount);
    }

    // @dev Convenience function, only call off chain for view
    // @return this contracts balance (users margin deposit) of a given token
    function balanceOf(address _token) public view returns (uint256){
        return IERC20Minimal(_token).balanceOf(address(this));
    }

    function approve(address token, uint2256 amount) external view returns (bool) {
        safeApprove(address(this), token, amount);
    }
}