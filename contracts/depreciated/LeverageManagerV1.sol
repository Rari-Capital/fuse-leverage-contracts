pragma solidity 0.8.9;
//"SPDX-License-Identifier: MIT"

// =============== Import Statements ===============

import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import './Pairflash.sol';

// ============= Interface Declarations ============

/**  */
interface FusePool {

}


/** @dev Specifies flash loan receiver */
interface IFlashLoanReceiver {

}


/** @dev Specifies flash loan receiver base */
interface IFlashLoanReceiverBase {

}

// ==================== Libraries ==================


/** @dev Specifies the fuse asset that ERC20 tokens are converted to in order to enter fuse positions */ 
interface FAsset {
	/**  Mints the fAsset (exchanges the underlying asset for fuse pool asset) */
	function mint(uint mintAmount) external returns (uint);

	/** enters borrow position of asset of specified borrow size */
	function borrow(uint borrowAmount) external returns (uint);

	// repays the borrow amount of the asset borrowed by the specified amount
	function repayBorrow(uint repayAmount) external returns (uint);

	// This can be used by the user on the website to repay on behalf of their position manager contract
	function repayBorrowBehalf(address borrower, uint repayAmount) external returns (uint);

	// Returns the underlying quantity of the asset supplied to the fToken
	function getCash() external returns (uint);

}


// ======== Contracts ========

contract LeverageManagerFactory is ReentrancyGuard {
	uint256 public constant fee = 0; //TODO: Determine fee

	mapping(address => address) public levManagers;
	mapping(address => address) public owners;
	// mapping(address => uint16) public decimals; TODO: Determine if this is needed


	function create() public nonReentrant {
		require(levManagers[msg.sender] != "0x0000000000000000000000000000000000000000"); // TODO: determine if string is right type
	}

	function getManager(address user) external returns(address) {
		return levManagers[user];
	}

}


contract LeverageManagerV1 is ReentrancyGuard, PairFlash {
	using SafeMath for uint;

	// ======== STORAGE VALUES =========

	// Most pools use a .3% fee. Future iterations will be dyanmic fees sent from FE
	uint24 constant fee = 3000;

	// owner is set upon constructing contract
	address immutable owner;

	// key : pool address , value : position struct
	mapping(address => Position) public positions;

	// key : token address , value : user's contract balance of token. Contributes to buying power
	mapping(address => uint256) public tokens;


	// position contains all the details of a current position
	// isChanged is a very useful value for saving gas if only the tail end of users are editing positons alot
	struct Position {
		address lToken;
		address lFToken;
		address bToken;
		address bFToken;
		uint256 lAmountOpen;
		uint256 bAmountOpen;
		bool isOpen;
	}


	// ========== EVENTS LOGS =========

	//
	event PoolCreated(address indexed poolAddress, address indexed sender);

	// @dev d and b refer to total deposit and borrow, c refers to "cover" or the amount of the position the user is covering 
	event PositionOpened(
		address indexed poolAddress, 
		address indexed sender, 
		address indexed lToken,
		address indexed bToken,
		uint256 lAmount,
		uint256 lEquity
	);

	event PositionIncreased(
		address indexed poolAddress,
		address indexed sender,
		address indexed lFToken,
		address indexed bFToken,
		uint256 lIncrease
	);

	event PositionDecreased(
		address indexed poolAddress, 
		address indexed sender,
		address indexed lToken,
		uint256 lPnl
	);


	// @dev Dinit is stored in the position struct so that an observer can easily record pnl 
	event PositionClosed(
		address indexed poolAddress,
		address indexed sender,
		address indexed lToken,
		address indexed bToken,
		uint256 bAmount
	);

	// ======== MODIFIERS =========

	// @dev owner in this case is the user's address who has deployed their LeverageManagerV1 proxy
	modifier onlyOwner {
		require(msg.sender == this.owner, "Permission Denied");
		_;
	}

	// constructor sets the owner of the proxy contract
	constructor() {
		this.owner = msg.sender;
	}

	// ===== EXTERNAL PURE FUNCTIONS =======

	
	// ===== EXTERNAL VIEW FUNCTIONS =======
	/**
	* @param pool The pool address (comptroller address) being queried
	* @return Position the user's position info of the given pool 
	*/
	function getPosition(address calldata pool) external view returns(Position) {
		return positions[pool];
	}

	function getPools() external view returns(address[])  {
		return pools;
	}

	function getBalance(address calldata token) external view returns(uint256)  {
		return(tokens[token]);
	}

	function isOpen(address calldata pool) external view returns(bool)  {
		return(positions[pool].isOpen);
	}


	// ========= EXTERNAL UTILITY FUNCTIONS ===========

	function approve(address _token) external onlyOwner {
		address memory sender = msg.sender;
		ERC20 token = ERC20(_token);
		require(token.approve(sender, token.balanceOf(sender)), "Approve Failed!");
	}

	/**
	* @dev    Funds contract with specified token, this impacts a users' buying power
	* @param  _token the address of the token to deposit
	* @return bool true if successful transfer
	 */
	function fund(
		address _token, 
		uint256 amount
		) external onlyOwner nonReentrant returns (bool){
		tokens[_token] += amount; // TODO: Double check for reentrancy attack
		ERC20 token = ERC20(_token);
		require(token.transfer(address(this), amount), "Tranfer Failed!");
	}


	/**
	* @dev Some math operations are UNSAFE given token decimals, please be sure to read comments!
	* @param pool Address of the fuse pool with the position to close
	* @param _lToken Address of the fToken being lended 
	* @param _bToken Address of the fToken being borrowed
	* @param lAmount uint256 amount of fTokens being lent
	* @param bAmount uint256 amount of the fTokens being borrowed
	* @param lEquity 
	* @param fee IMPORTANT, set this to 3000 by default unless ur sure other fee pools exist 
	* @return bool success(1) or failure(0)
	*/
	function openPosition(
		address _pool, 
		address _lToken,
		address _lFToken, 
		address _bToken,
		address _bFToken,
		uint256 lAmount,
		uint256 lEquity,
		uint24 fee
		) public payable onlyOwner nonReentrant returns (bool) {
			// Math does not support this function editing the size of a position,
			// please use increase/decrease position for that!
			require(!positions[pool].isOpen, "Position Still Open");
			require(lAmount > lEquity, "lend amount too small");
			require(tokens[_lToken] >= lEquity, "Insufficient Equity");
			
			// Initialize tokens to query
			ERC20 lToken = new ERC20(_lToken);
			ERC20 bToken = new ERC20(_bToken);
			FAsset lFToken = new FAsset(_lFToken);
			FAsset bFToken = new FAsset(_bFToken);

			// Initialize decimals for tokens
			uint256 lDecimals = lToken.decimals();
			uint256 bDecimals = bToken.decimals();

			// Resolves potential decimal disparity between tokens' decimals
			// @Dev UNSAFE pls make sure to round out lDec-bDec if lDec >= bDec 
			if(lDecimals == bDecimals) {
				uint256 bAmount = lAmount;
			} else { 
				uint256 bAmount = (lDecimals > bDecimals) ? 
				lAmount.div(10**(lDecimals.sub(bDecimals))):
				lAmount.mul(10**(bDecimals.sub(lDecimals))); 
			}

			
			// 1) get flash loan of lend token 
			// lAmount is the total 
			uint256 borrow = lAmount - lEquity;
			tokens[_lToken] += borrow; 
			// uint256 feeAmt = ((lAmount*3) /997) +1;

			

			FlashParams params = new FlashParams(_lToken, _bToken, fee, borrow, 0, fee, fee);
			require(initFlash(params), "Flash init failed");
			uint256 lFee = lAmount / 3000;
			FlashCallbackData callback = new FlashCallbackData();


			// Mint fuse tokens from lend and borrows the btoken to pay back the loan
			
			

			lFToken.mint(lAmount); 

			tokens[_btoken] += bAmount;
			
			require(bFToken.borrow(bAmount))





			// 3) borrow $ equivalent of lend token + extra to pay flashloan 
				// calc borrow amount
				// lBToken.borrow(bAmount)

			// 4) pay back flash loan with borrowed token
				// pay back using bToken bAmount 

			deposit(); 
			// Deposit the contracts lend tokens (total - step 2 amount) into fuse 
			// Borrow token according to inputs 
			// Pay back the flash loan
			// Done, emit event!
			emit PositionOpened(); // TODO: implement this!
	}


	/**
	* @dev 
	* @param pool          address of the pool of which the user's position will be edited
	* @param magnitude     0 if decreasing 1 if increasing
	* @param lChangeAmount 
	* @return bool 
	 */
	function editPosition(
		address calldata pool,
		address calldata _lend,
		address calldata _borrow,
		address calldata _lendUnderlying,
		address calldata _borrowUnderlying,
		bool calldata magnitude,
		uint256 calldata lChangeAmount
	) external onlyOwner nonReentrant returns (bool)  {
		uint256 memory size = positons[pool].lAmountCurr;

		if(magnitude == 0)  {
			// change the lamount and b amount curr 
			// do flash loan
		
		} else {
			// change the lamount and b amount curr 
			// do flash loan
		}
		emit PositionChanged(); //TODO: implement this!
	}

	/**
	* @dev   F
	* @param pool Address of the fuse pool with the position to close
	* @param _lToken Address of the fToken being lended 
	* @param _bToken Address of the fToken being borrowed
	* @param lAmount uint256 amount of fTokens being lent
	* @param bAmount uint256 amount of the fTokens being borrowed
	*/
	function decreasePosition(
		address pool,
		address _lToken,
		address _bToken,
		uint256 lAmount,
		uint256 bAmount
	) public onlyOwner nonReentrant {
		// TODO: do all of this shit bruh
		Position memory pos = positions[pool];
		require(pos.isOpen, "Position Closed");
		
		//TODO: do i add this back?
		// pos.lAmountCurr -= lAmount; 
		
		// 1) take flash loan equal to lend amount change 
		

		// 2) repay borrow with flash loan 

		// 3) redeem lend amount from lend token 

		// 4) pay flash loan back 


		// do rest of transaction


	}

	/**
	*
	*
	 */
	function increasePosition(
		address pool,
		uint256 lAmountIncrese
	) external onlyOwner nonReentrant {

		Position memory pos = positions[pool];
		require(pos.isOpen, "Position Closed");
		require(1 == 1); // TODO: Require that the leverage doesnt trigger liquidation
		// If the position has already been editied, then the curr values are correct and can be added to. 
		// Otherwise, the curr values are from a previous position or unset and will be rewritten!

		// TODO: implement this
		if(!pos.isChanged) {
			pos.isChanged = true;
			pos.bAmountCurr = 0; 
			pos.lAmountCurr = 0; 
		} else {
			pos.bAmountCurr += 0; 
			pos.lAmountCurr += 0; 
		}

		// curr lev - goal lev gives you the deposit amount required
		// the balance of this contract lToken determine
	}

	/**
	* @dev 
	* @param pool The pool address  
	*/
	function closePositionFull(
		address pool,
		address _lToken,
		address _bToken,
		address lend
	) external onlyOwner nonReentrant {
		this.isOpen = false;

		// Take flash loan to pay back borrow 
		// Pay borrow 
		// Withdraw lend
		// Pay flash loan with lend 
		// Return remaining lend to user (pnl) 
	}

	


}

