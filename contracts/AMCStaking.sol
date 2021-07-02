pragma solidity 0.6.12;

import '@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol';
import '@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol';
import '@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol';
import "./AMCInterface.sol";

contract AMCStaking {
  using SafeMath for uint256;
  using SafeBEP20 for IBEP20;
  // Info of each user.
  struct UserInfo {
    uint256 amount;         // How many LP tokens the user has provided.
    uint256 rewardDebt;     // Reward debt.
  }

  uint256 public lastRewardBlock;  // Last block number that AMCs distribution occurs.
  uint256 public accAmcPerShare;   // Accumulated AMCs per share, times 1e12. See below.

  // The AMC TOKEN!
  IBEP20 public amc;
  // AMC tokens created per block.
  uint256 public amcPerBlock;    // should be defined 60% of total emission
  // Info of each user that stakes AMC tokens.
  mapping(address => UserInfo) public userInfo;

  event Deposit(address indexed user, uint256 amount);
  event Withdraw(address indexed user, uint256 amount);
  event EmergencyWithdraw(address indexed user, uint256 amount);
  
  constructor(
    IBEP20 _amc,
    uint256 _amcPerBlock
  ) public {
      amc = _amc;
      amcPerBlock = _amcPerBlock;
      lastRewardBlock = block.number;
  }

  // Return reward multiplier over the given _from to _to block.
  function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
    return _to.sub(_from);
  }

  // View function to see pending AMCs on frontend.
  function pendingAmc(address _user) external view returns (uint256) {
    UserInfo storage user = userInfo[_user];
    uint256 lpSupply = amc.balanceOf(address(this));
    uint256 _accAmcPerShare = accAmcPerShare;
    if (block.number > lastRewardBlock && lpSupply != 0) {
        uint256 multiplier = getMultiplier(lastRewardBlock, block.number);
        uint256 amcReward = multiplier.mul(amcPerBlock);
        _accAmcPerShare = _accAmcPerShare.add(amcReward.mul(1e12).div(lpSupply));
    }
    return user.amount.mul(_accAmcPerShare).div(1e12).sub(user.rewardDebt);
  }

  // Update reward variables of the given pool to be up-to-date.
  function updatePool() public {
    if (block.number <= lastRewardBlock) {
        return;
    }
    uint256 lpSupply = amc.balanceOf(address(this));
    if (lpSupply == 0) {
        lastRewardBlock = block.number;
        return;
    }
    uint256 multiplier = getMultiplier(lastRewardBlock, block.number);
    uint256 amcReward = multiplier.mul(amcPerBlock);
    AMCInterface(address(amc)).mint();
    accAmcPerShare = accAmcPerShare.add(amcReward.mul(1e12).div(lpSupply));
    lastRewardBlock = block.number;
  }

  // Withdraw without caring about rewards. EMERGENCY ONLY.
  function emergencyWithdraw() public  {
    UserInfo storage user = userInfo[msg.sender];
    uint256 amount = user.amount;
    user.amount = 0;
    user.rewardDebt = 0;
    amc.safeTransfer(address(msg.sender), amount);
    emit EmergencyWithdraw(msg.sender, amount);
  }

  // Stake AMC tokens to MasterChef
  function enterStaking(uint256 _amount) public {
    UserInfo storage user = userInfo[msg.sender];
    updatePool();
    if (user.amount > 0) {
        uint256 pending = user.amount.mul(accAmcPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            amc.safeTransfer(msg.sender, pending);
        }
    }
    if(_amount > 0) {
        amc.safeTransferFrom(address(msg.sender), address(this), _amount);
        user.amount = user.amount.add(_amount);
    }
    user.rewardDebt = user.amount.mul(accAmcPerShare).div(1e12);
    emit Deposit(msg.sender, _amount);
  }

  // Withdraw AMC tokens from STAKING.
  function leaveStaking(uint256 _amount) public {
    UserInfo storage user = userInfo[msg.sender];
    require(user.amount >= _amount, "withdraw: not good");
    updatePool();
    uint256 pending = user.amount.mul(accAmcPerShare).div(1e12).sub(user.rewardDebt);
    if(pending > 0) {
        amc.safeTransfer(msg.sender, pending);
    }
    if(_amount > 0) {
        user.amount = user.amount.sub(_amount);
        amc.safeTransfer(address(msg.sender), _amount);
    }
    user.rewardDebt = user.amount.mul(accAmcPerShare).div(1e12);
    emit Withdraw(msg.sender, _amount);
  }
}