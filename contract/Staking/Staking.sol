// SPDX-License-Identifier: MIT

pragma solidity ^0.6.6;

import "../_lib/SafeMath.sol";
import "../_lib/ERC20.sol";
import "../_lib/Ownable.sol";

interface IPokerToken {
    function totalSupply() external view returns (uint256);

    function balanceOf(address _owner) external view returns (uint256);

    function transfer(address _to, uint256 _amount) external returns (bool);

    function transferFrom(
        address _from,
        address _to,
        uint256 _amount
    ) external returns (bool);

    function mint(address _to, uint256 _amount) external;

    function burn(uint256 _amount) external;
}

interface IBurnCoin {
    function burn(uint256 _amount) external;
}

contract Staking {
    using SafeMath for uint256;
    IPokerToken poker;
    IBurnCoin burnCoin;
    address public owner;

    constructor(IPokerToken _poker, IBurnCoin _burncoin) public {
        poker = _poker;
        owner = msg.sender;
        lastUpdateTime = getTime();
        burnCoin = _burncoin;
    }

    struct UserInfo {
        uint256 shares;
        uint256 lastDepositedTime;
        uint256 lastUserActionTime;
        uint256 rewardDebt;
        uint256 rewards;
        uint256 amount;
    }

    uint256 public accPerShare = 0;
    uint256 public totalShares = 0;
    uint256 public totalAmount = 0;
    uint256 public lastUpdateTime = 0;
    uint256 public withdrawFee = 1000;
    uint256 public withdrawFeePeriod = 7 days; // 7 days
    //uint256 public withdrawFeePeriod = 10 minutes; // 测试用
    uint256 public stakingStartTime = 0;
    bool public stakingSwitch = false;
    uint256 decimals = 18;

    uint256 constant ONE = 10**18;

    function divFloor(uint256 target, uint256 d)
        internal
        pure
        returns (uint256)
    {
        return target.mul(ONE).div(d);
    }

    function decimalMul(uint256 target, uint256 d)
        internal
        pure
        returns (uint256)
    {
        return target.mul(d) / ONE;
    }

    mapping(address => UserInfo) public userInfo;

    event Deposit(
        address indexed sender,
        uint256 amount,
        uint256 shares,
        uint256 lastDepositedTime
    );
    event Withdraw(address indexed sender, uint256 amount, uint256 shares);

    function deposit(uint256 _amount) public {
        require(_amount > 0, "Nothing to deposit");

        updatePool();
        UserInfo storage user = userInfo[msg.sender];

        if (user.amount > 0) {
            uint256 pending = decimalMul(user.amount, accPerShare).sub(
                user.rewardDebt
            );
            //totalAmount = totalAmount.sub(pending);
            user.rewards = user.rewards.add(pending);
        } else user.rewards = 0;

        poker.transferFrom(msg.sender, address(this), _amount);

        uint256 currentShares = _amount.mul(getEther());
        /*
        if (totalShares != 0) {
            currentShares = (_amount.mul(totalShares)).div(totalAmount);
        } else {
            currentShares = _amount.mul(getEther());
        }
        */

        user.shares = user.shares.add(currentShares);
        totalShares = totalShares.add(currentShares);

        user.amount = user.amount.add(_amount);
        user.rewardDebt = decimalMul(user.amount, accPerShare);

        user.lastUserActionTime = getTime();
        user.lastDepositedTime = getTime();

        emit Deposit(msg.sender, _amount, currentShares, block.timestamp);
    }

    function withdraw(uint256 _shares) public {
        UserInfo storage user = userInfo[msg.sender];
        require(_shares > 0, "Nothing to withdraw");
        require(_shares <= user.shares, "Withdraw amount exceeds balance");

        updatePool();

        //用户所有收益
        uint256 userTotalAmount = decimalMul(user.amount, accPerShare)
            .sub(user.rewardDebt)
            .add(user.rewards);

        //提取收益部分的份额
        uint256 withdrawAmount = userTotalAmount.mul(_shares).div(user.shares);

        //提取原账户中的份额
        uint256 userAmount = user.amount.mul(_shares).div(user.shares);

        user.shares = user.shares.sub(_shares);
        totalShares = totalShares.sub(_shares);

        require(
            totalAmount >= withdrawAmount,
            "Withdraw amount exceeds balance"
        );

        //矿池-待提收益
        totalAmount = totalAmount.sub(withdrawAmount);

        //历史收益
        user.rewards = userTotalAmount.sub(withdrawAmount);

        //实际提取总数
        withdrawAmount = withdrawAmount.add(userAmount);

        if (getTime() < user.lastDepositedTime.add(withdrawFeePeriod)) {
            uint256 currentWithdrawFee = withdrawAmount.mul(100).div(10000);
            withdrawAmount = withdrawAmount.sub(currentWithdrawFee);
            poker.transfer(address(burnCoin), currentWithdrawFee);
            burnCoin.burn(currentWithdrawFee);
        }

        poker.transfer(msg.sender, withdrawAmount);
        user.amount = user.amount.sub(userAmount);

        if (user.shares > 0)
            user.rewardDebt = decimalMul(user.amount, accPerShare);

        user.lastUserActionTime = block.timestamp;

        emit Withdraw(msg.sender, withdrawAmount, _shares);
    }

    function updatePool() public {
        uint256 curTime = getTime();
        if (curTime <= lastUpdateTime) {
            return;
        }

        if (totalShares <= 0) {
            lastUpdateTime = curTime;
            return;
        }

        uint256 multiplier = now - lastUpdateTime;
        uint256 reward = multiplier.mul(getStakingCoinPerSec());
        lastUpdateTime = curTime;
        totalAmount = totalAmount.add(reward);
        accPerShare = accPerShare.add(divFloor(reward, this.totalDeposit())); //一个单位的份额价值更新
        poker.mint(address(this), reward);
    }

    function pendingCoin() external view returns (uint256) {
        uint256 curTime = getTime();
        if (totalShares <= 0) {
            return 0;
        }
        uint256 multiplier = curTime - lastUpdateTime;
        uint256 reward = multiplier.mul(getStakingCoinPerSec());
        return reward;
    }

    function totalStakingAmount() public view returns (uint256) {
        return this.pendingCoin().add(getDepositBalance());
    }

    function totalDeposit() external view returns (uint256) {
        return totalShares.div(ONE);
    }

    function computePer() external view returns (uint256) {
        return
            accPerShare.add(divFloor(this.pendingCoin(), this.totalDeposit()));
    }

    function myBenefits() public view returns (uint256) {
        UserInfo storage user = userInfo[msg.sender];
        if (user.shares == 0) {
            return 0;
        }

        uint256 ben = decimalMul(user.amount, this.computePer());

        if (ben > user.rewardDebt) return ben.sub(user.rewardDebt);
        else return 0;
    }

    function myValue() public view returns (uint256) {
        UserInfo storage user = userInfo[msg.sender];
        if (user.shares == 0) return 0;
        return
            decimalMul(user.amount, this.computePer())
                .sub(user.rewardDebt)
                .add(user.rewards)
                .add(user.amount);
    }

    function sharesPrice() public view returns (uint256) {
        if (totalShares == 0) return 0;
        return totalShares.mul(this.computePer()).div(totalShares);
    }

    // function getTime()
    function getTime() public view returns (uint256) {
        return now;
    }

    function getDepositBalance() public view returns (uint256) {
        return poker.balanceOf(address(this));
    }

    function getEther() public view returns (uint256) {
        return 10**uint256(decimals);
    }

    //todo 当前是测试时间
    function getStakingCoinPerSec() public view returns (uint256) {
        uint256 sec = 24 * 3600;
        uint256 curTime = getTime();
        uint256 coin = 1;

        if (stakingSwitch == false) {
            //uint256 maxCoin = 122300;
            coin = 12000000000000; //maxCoin.mul((10**uint256(decimals))).div(sec);
            return coin;
        }

        // 24 * 3600 * 7 * 2
        if (curTime < (stakingStartTime + 60 * 5)) {
            uint256 maxCoin = 2800000;
            coin = maxCoin.mul((10**uint256(decimals))).div(sec);
        }
        // 24 * 3600 * 7 * 4
        else if (curTime < (stakingStartTime + 60 * 10)) {
            uint256 maxCoin = 1400000;
            coin = maxCoin.mul((10**uint256(decimals))).div(sec);
        } else {
            uint256 maxCoin = 122300;
            coin = maxCoin.mul((10**uint256(decimals))).div(sec);
        }
        return coin;
    }

    function setStakingSwitch(bool flag) public {
        if (msg.sender == owner) {
            if (flag) {
                stakingStartTime = getTime();
            } else {
                stakingStartTime = 0;
            }
            stakingSwitch = flag;
        }
    }
}
