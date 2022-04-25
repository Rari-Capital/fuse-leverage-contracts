pragma solidity >=0.7.6;

import './Clones.sol';
import './LeverageManager.sol';

contract LeverageManagerFactory is Clones {

    address immutable managerImplementation;
    address immutable owner;

    bool public newUserLock;

    mapping(address => address) public ownerOfManager; 

    event ManagerMade(address indexed manager, address indexed user);
    event AdditonalUsersLocked(string message);
    event AdditionalUsersUnlocked(string message);

    constructor(address impl)  {
        managerImplementation = impl;
        newUserLock = true;
    }

    function makeClone() external {
        require(!newUserLock, "New Users Locked");
        require(ownerOfManager[msg.sender] == address(0), "Manager Exists");

        address _manager = clone(managerImplementation);
        LeverageManager(_manager).initialize(msg.sender);
        ownerOfManager[msg.sender] = _manager;

        // callback safety measure
        approvedManager[_manager] = true;
        
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