pragma solidity >=0.7.6;

import './Clones.sol';
import './AccountData.sol';
import './Pairflash.sol';
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';

contract LeverageManagerFactory is Clones {

    address immutable managerImplementation;
    address immutable owner;
    ISwapRouter public immutable swapRouter;


    bool public newUserLock;

    mapping(address => address) public managers;

    event ManagerMade(address indexed manager, address indexed user);
    event AdditonalUsersLocked(string message);
    event AdditionalUsersUnlocked(string message);

    constructor(address _master, address _swapRouter)  {
        managerImplementation = _master;
        swapRouter = ISwapRouter(_swapRouter);
        newUserLock = true;
    }

    function makeClone() external {
        require(!newUserLock, "New Users Locked");
        require(managers[msg.sender] == address(0), "Manager Exists");

        address _manager = clone(managerImplementation);
        PairFlash(_manager).initialize(swapRouter, msg.sender);
        managers[msg.sender] = _manager;
        assert(address(_manager) != address(0), "Major Clone Error");
        
        emit ManagerMade(_manager, msg.sender);
    }

    function lockAdditionalUsers() external {
        require(msg.sender == owner);
        newUserLock = true;
        emit AdditonalUsersLocked("Locked");
    }

    function unlockAdditionalUsers() external {
        require(msg.sender == owner);
        newUserLock = false;
        emit AdditionalUsersUnlocked("Unlocked");
    }


}