pragma solidity ^0.6.2;

import "./lib/BEP20.sol";
import "./lib/IUniswapV2Pair.sol";
import "./lib/IUniswapV2Factory.sol";
import "./lib/IUniswapV2Router.sol";
import "./lib/PrizePoolInterface.sol";

contract AMCToken is BEP20 {
    using SafeMath for uint256;

    uint256 public constant STAKING_SHARE = 600;  // distributioin rate for staking over 1e3 = 60%
    uint256 public constant DEV_SHARE = 100;      // distributioin rate for developer fee over 1e3 = 10%
    uint256 public constant MANAGER_SHARE = 300;  // distributioin rate for manager over 1e3 = 30%
    
    address public stakingAddr;
    address public devAddr;
    address public managerAddr;
    address public liquidityWallet;

    // AMC tokens created per block.
    uint256 public amcPerBlock;
    // block number in which mint function is called for the last time.
    uint256 public lastMintBlock;

    uint256 public constant liquidityFee = 50;
    uint256 public constant bnbPrizeFee = 25;
    uint256 public constant burnRate = 25;

    uint256 public immutable deployDate;  // timestamp on which this smart contract is deployed

    IUniswapV2Router02 public uniswapV2Router;
    address public immutable uniswapV2Pair;
    bool private swapping;

    PrizePoolInterface public bnbPool;
    address public bnbSponsorhip;

    constructor (
        address _devAddr,
        address _managerAddr,
        uint256 _amcPerBlock,
        PrizePoolInterface _bnbPool,
        address _bnbSponsorhip
    ) public BEP20("Amc Token", "AMC") {
        // init distribution wallets
        devAddr = _devAddr;
        managerAddr = _managerAddr;
        amcPerBlock = _amcPerBlock;
        lastMintBlock = block.number;
        _mint(msg.sender, 1e5 ether); // initial supply to dev wallet
        deployDate = block.timestamp;

        liquidityWallet = owner();
        bnbPool = _bnbPool;
        bnbSponsorhip = _bnbSponsorhip;

        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0xD99D1c33F9fC3444f8101754aBC46c52416550D1);
         // Create a uniswap pair for this new token
        address _uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = _uniswapV2Pair;

        _setAutomatedMarketMakerPair(_uniswapV2Pair, true);
    }

    // store addresses that a automatic market maker pairs. Any transfer *to* these addresses
    // could be subject to a maximum transfer amount
    mapping (address => bool) public automatedMarketMakerPairs;

    /// @dev A record of each accounts delegate
    mapping (address => address) internal _delegates;

    /// @notice A checkpoint for marking number of votes from a given block
    struct Checkpoint {
        uint32 fromBlock;
        uint256 votes;
    }

    /// @notice A record of votes checkpoints for each account, by index
    mapping (address => mapping (uint32 => Checkpoint)) public checkpoints;

    /// @notice The number of checkpoints for each account
    mapping (address => uint32) public numCheckpoints;

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// @notice The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant DELEGATION_TYPEHASH = keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    /// @notice A record of states for signing / validating signatures
    mapping (address => uint) public nonces;

      /// @notice An event thats emitted when an account changes its delegate
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);

    /// @notice An event thats emitted when a delegate account's vote balance changes
    event DelegateVotesChanged(address indexed delegate, uint previousBalance, uint newBalance);

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );

    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);

    function setStaking(address _stakeAddr) public onlyOwner {
        require(stakingAddr == address(0), 'staking address can`t be reset');
        stakingAddr = _stakeAddr;
    }

    function setDevWallet(address _devWallet) public onlyOwner {
        devAddr = _devWallet;
    }

    function setManagerWallet(address _managerWallet) public onlyOwner {
        managerAddr = _managerWallet;
    }

    function mint() public {
        uint256 blockNumberPassed = block.number.sub(lastMintBlock);
        uint256 amount = amcPerBlock.mul(blockNumberPassed);
        lastMintBlock = block.number;
        _distribute(amount);
    }

    function _distribute(
        uint256 _amount
    ) 
        internal 
    {
        // _mint(_to, _amount);
        // _moveDelegates(address(0), _delegates[_to], _amount);
        uint256 staking_amount = _amount.mul(STAKING_SHARE).div(1000);
        uint256 dev_fee = _amount.mul(DEV_SHARE).div(1000);
        uint256 manage_cost = _amount.mul(MANAGER_SHARE).div(1000);

        _mint(stakingAddr, staking_amount);
        _mint(devAddr, dev_fee);
        _mint(managerAddr, manage_cost);

        _moveDelegates(address(0), _delegates[stakingAddr], staking_amount);
        _moveDelegates(address(0), _delegates[devAddr], dev_fee);
        _moveDelegates(address(0), _delegates[managerAddr], manage_cost);
    }

    receive() external payable {

  	}

    function SaleFee() public returns (uint256) {
        uint diff = block.timestamp.sub(deployDate).div(86400);
        if (diff >= 10) return 0;
        return 40 - diff.mul(4);
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        require(automatedMarketMakerPairs[pair] != value, "AMC: Automated market maker pair is already set to that value");
        automatedMarketMakerPairs[pair] = value;
        emit SetAutomatedMarketMakerPair(pair, value);
    }  

    function swapAndLiquify(uint256 tokens) private {
        // split the contract balance into halves
        uint256 half = tokens.div(2);
        uint256 otherHalf = tokens.sub(half);

        // capture the contract's current ETH balance.
        // this is so that we can capture exactly the amount of ETH that the
        // swap creates, and not make the liquidity event include any ETH that
        // has been manually sent to the contract
        uint256 initialBalance = address(this).balance;

        // swap tokens for ETH
        swapTokensForEth(half); // <- this breaks the ETH -> HATE swap when swap+liquify is triggered

        // how much ETH did we just swap into?
        uint256 newBalance = address(this).balance.sub(initialBalance);

        // add liquidity to uniswap
        addLiquidity(otherHalf, newBalance);
        
        emit SwapAndLiquify(half, newBalance, otherHalf);
    }

    function swapTokensForEth(uint256 tokenAmount) private {

        
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
        
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            liquidityWallet,
            block.timestamp
        );
        
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        if( 
        	!swapping &&
            automatedMarketMakerPairs[to] && // sells only by detecting transfer to automated market maker pair
        	from != address(uniswapV2Router) //router -> pair is removing liquidity which shouldn't have max
        ) {
            if(
                !automatedMarketMakerPairs[from] &&
                from != liquidityWallet &&
                to != liquidityWallet
            ) {
                uint256 totalSaleFeeRate = SaleFee();
                if (totalSaleFeeRate != 0) {
                    uint256 fees = amount.mul(SaleFee()).div(100);

                    amount = amount.sub(fees);

                    super._transfer(from, address(this), fees);
                    swapping = true;
                    uint256 swapTokens = fees.mul(liquidityFee).div(100);
                    uint256 bnbShare = fees.mul(bnbPrizeFee).div(100);
                    uint256 burnShare = fees.sub(swapTokens).sub(bnbShare);
                    swapAndLiquify(swapTokens);
                    swapTokensForEth(bnbShare);
                    bnbPool.depositTo{value: address(this).balance}(
                        address(managerAddr),
                        address(this).balance,
                        address(bnbSponsorhip),
                        address(this)
                    );
                    super._burn(address(this), burnShare);
                    swapping = false;
                }
            }
        }
        super._transfer(from, to, amount);        
    }

    /**
     * @notice Delegate votes from `msg.sender` to `delegatee`
     * @param delegator The address to get delegatee for
     */
    function delegates(address delegator)
        external
        view
        returns (address)
    {
        return _delegates[delegator];
    }

   /**
    * @notice Delegate votes from `msg.sender` to `delegatee`
    * @param delegatee The address to delegate votes to
    */
    function delegate(address delegatee) external {
        return _delegate(msg.sender, delegatee);
    }

    /**
     * @notice Delegates votes from signatory to `delegatee`
     * @param delegatee The address to delegate votes to
     * @param nonce The contract state required to match the signature
     * @param expiry The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function delegateBySig(
        address delegatee,
        uint nonce,
        uint expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
    {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes(name())),
                getChainId(),
                address(this)
            )
        );

        bytes32 structHash = keccak256(
            abi.encode(
                DELEGATION_TYPEHASH,
                delegatee,
                nonce,
                expiry
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                structHash
            )
        );

        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "AMC::delegateBySig: invalid signature");
        require(nonce == nonces[signatory]++, "AMC::delegateBySig: invalid nonce");
        require(now <= expiry, "AMC::delegateBySig: signature expired");
        return _delegate(signatory, delegatee);
    }

    /**
     * @notice Gets the current votes balance for `account`
     * @param account The address to get votes balance
     * @return The number of current votes for `account`
     */
    function getCurrentVotes(address account)
        external
        view
        returns (uint256)
    {
        uint32 nCheckpoints = numCheckpoints[account];
        return nCheckpoints > 0 ? checkpoints[account][nCheckpoints - 1].votes : 0;
    }

    /**
     * @notice Determine the prior number of votes for an account as of a block number
     * @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
     * @param account The address of the account to check
     * @param blockNumber The block number to get the vote balance at
     * @return The number of votes the account had as of the given block
     */
    function getPriorVotes(address account, uint blockNumber)
        external
        view
        returns (uint256)
    {
        require(blockNumber < block.number, "AMC::getPriorVotes: not yet determined");

        uint32 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent balance
        if (checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
            return checkpoints[account][nCheckpoints - 1].votes;
        }

        // Next check implicit zero balance
        if (checkpoints[account][0].fromBlock > blockNumber) {
            return 0;
        }

        uint32 lower = 0;
        uint32 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint32 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            Checkpoint memory cp = checkpoints[account][center];
            if (cp.fromBlock == blockNumber) {
                return cp.votes;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return checkpoints[account][lower].votes;
    }

    function _delegate(address delegator, address delegatee)
        internal
    {
        address currentDelegate = _delegates[delegator];
        uint256 delegatorBalance = balanceOf(delegator); // balance of underlying AMCs (not scaled);
        _delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);

        _moveDelegates(currentDelegate, delegatee, delegatorBalance);
    }

    function _moveDelegates(address srcRep, address dstRep, uint256 amount) internal {
        if (srcRep != dstRep && amount > 0) {
            if (srcRep != address(0)) {
                // decrease old representative
                uint32 srcRepNum = numCheckpoints[srcRep];
                uint256 srcRepOld = srcRepNum > 0 ? checkpoints[srcRep][srcRepNum - 1].votes : 0;
                uint256 srcRepNew = srcRepOld.sub(amount);
                _writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
            }

            if (dstRep != address(0)) {
                // increase new representative
                uint32 dstRepNum = numCheckpoints[dstRep];
                uint256 dstRepOld = dstRepNum > 0 ? checkpoints[dstRep][dstRepNum - 1].votes : 0;
                uint256 dstRepNew = dstRepOld.add(amount);
                _writeCheckpoint(dstRep, dstRepNum, dstRepOld, dstRepNew);
            }
        }
    }

    // voting related functions
    function _writeCheckpoint(
        address delegatee,
        uint32 nCheckpoints,
        uint256 oldVotes,
        uint256 newVotes
    )
        internal
    {
        uint32 blockNumber = safe32(block.number, "AMC::_writeCheckpoint: block number exceeds 32 bits");

        if (nCheckpoints > 0 && checkpoints[delegatee][nCheckpoints - 1].fromBlock == blockNumber) {
            checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
        } else {
            checkpoints[delegatee][nCheckpoints] = Checkpoint(blockNumber, newVotes);
            numCheckpoints[delegatee] = nCheckpoints + 1;
        }

        emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }

    function safe32(uint n, string memory errorMessage) internal pure returns (uint32) {
        require(n < 2**32, errorMessage);
        return uint32(n);
    }

    function getChainId() internal pure returns (uint) {
        uint256 chainId;
        assembly { chainId := chainid() }
        return chainId;
    }
}