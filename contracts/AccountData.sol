pragma solidity >=0.7.6;

contract AccountData {

    
    address constant fee = 3000;
    address constant factory = address(""); // TODO: get address 
    address constant _WETH9 = address(""); // TODO: get address
    ISwapRouter constant swapRouter = ISwapRouter(""); // TODO: get address 


    address public owner;

    mapping(address => position) private positions;
    mapping(address => mapping(address => uint256)) public tokens;

    struct Position {
        address token0;
        address token1;
        address ftoken0;
        address fToken1;
        uint256 principle;
        uint256 loan;
        bool isOpen; 
    }

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

    function chown(address _newOwner) external {
        require(msg.sender == owner);
        owner = _newOwner;
    }
    
    
}