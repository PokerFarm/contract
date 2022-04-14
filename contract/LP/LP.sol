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

interface ILPToken {
    function totalSupply() external view returns (uint256);

    function balanceOf(address _owner) external view returns (uint256);

    function transfer(address _to, uint256 _amount) external returns (bool);

    function transferFrom(
        address _from,
        address _to,
        uint256 _amount
    ) external returns (bool);
}

interface IBurnCoin {
    function burn(uint256 _amount) external;
}

contract LP {
    using SafeMath for uint256;
    IPokerToken poker;
    ILPToken lp;
    IBurnCoin burnCoin;
    address public owner;
    address public newContractAddress;

    constructor(
        IPokerToken _poker,
        ILPToken _lp,
        IBurnCoin _burncoin
    ) public {
        poker = _poker;
        owner = msg.sender;
        lastUpdateTime = getTime();
        burnCoin = _burncoin;
        lp = _lp;
    }

    struct UserInfo {
        uint256 shares;
        uint256 lastDepositedTime;
        uint256 lastUserActionTime;
        uint256 coinAtlastUserAction;
        uint256 coinPerShares;
        uint256 rewardDebt;
        uint256 rewards;
        uint256 amount;
    }
    uint256 public accPerShare = 0;
    uint256 public totalLpFee = 0;
    uint256 public totalShares = 0;
    uint256 public totalAmount = 0;
    uint256 public lastUpdateTime = 0;
    uint256 public withdrawFeePeriod = 7 days;       // 7 days
    //uint256 public withdrawFeePeriod = 10 minutes; // 测试用
    uint256 public stakingStartTime = 0;
    bool public stakingSwitch = false;
    uint256 decimals = 18;

    uint256 constant ONE = 10**18;
    function divFloor(uint256 target, uint256 d) internal pure returns (uint256) {
        return target.mul(ONE).div(d);
    }
    function decimalMul(uint256 target, uint256 d) internal pure returns (uint256) {
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
        uint256 bal = lpBalance();

        UserInfo storage user = userInfo[msg.sender];

        if (user.amount > 0) {
            uint256 pending = decimalMul(user.amount, accPerShare).sub(
                user.rewardDebt
            );
            //totalAmount = totalAmount.sub(pending);
            user.rewards = user.rewards.add(pending);
        }
        else
            user.rewards = 0;

        lp.transferFrom(msg.sender, address(this), _amount);

        uint256 currentShares = 0;
        if (totalShares != 0) {
            currentShares = (_amount.mul(totalShares)).div(bal);
        } else {
            currentShares = _amount.mul(getEther());
        }

        user.shares = user.shares.add(currentShares);
        totalShares = totalShares.add(currentShares);
        user.coinAtlastUserAction = user.rewards;

        user.amount = user.amount.add(_amount);
        user.rewardDebt = decimalMul(user.amount,accPerShare);

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
        uint256 userTotalAmount =  decimalMul(user.amount,accPerShare).sub(user.rewardDebt).add(user.rewards);
        //份额计算赎回多少比例收益
        uint256 withdrawAmount = userTotalAmount.mul(_shares).div(user.shares);

        uint256 curLp = user.amount.mul(_shares).div(user.shares);
        user.shares = user.shares.sub(_shares);
        totalShares = totalShares.sub(_shares);

        require(
            totalAmount >= withdrawAmount,
            "Withdraw amount exceeds balance"
        );

        totalAmount = totalAmount.sub(withdrawAmount);
        
        //历史收益
        user.rewards = userTotalAmount.sub(withdrawAmount);

        //手续费之前sub
        user.amount = user.amount.sub(curLp);

        if (getTime() < user.lastDepositedTime.add(withdrawFeePeriod)) {
            uint256 fee = curLp.mul(100).div(10000);
            curLp = curLp.sub(fee);
            totalLpFee = totalLpFee.add(fee);
        }

        lp.transfer(address(msg.sender), curLp);
        poker.transfer(msg.sender, withdrawAmount);

        if (user.shares > 0) {
            user.rewardDebt = decimalMul(user.amount,accPerShare);
            user.coinPerShares = sharesPrice();
            user.coinAtlastUserAction = user.rewards;
        } else 
            user.coinPerShares = 0;

        user.lastUserActionTime = block.timestamp;

        emit Withdraw(msg.sender, withdrawAmount, _shares);
    }

    function lpBalance() public view returns (uint256) {
        return lp.balanceOf(address(this)).sub(totalLpFee);
    }

    function updatePool() public {
        uint256 curTime = getTime();
        if (curTime <= lastUpdateTime) {
            return;
        }
        uint256 lpb = lpBalance();
        if (lpb <= 0) {
            lastUpdateTime = curTime;
            return;
        }

        uint256 multiplier = now - lastUpdateTime;
        uint256 reward = multiplier.mul(getStakingCoinPerSec());
        lastUpdateTime = curTime;
        totalAmount = totalAmount.add(reward);
        accPerShare = accPerShare.add(divFloor(reward,lpb));
        poker.mint(address(this), reward);
    }

    function pendingCoin() external view returns (uint256) {
        uint256 curTime = getTime();
        if (lpBalance() <= 0) {
            return 0;
        }
        uint256 multiplier = curTime - lastUpdateTime;
        uint256 reward = multiplier.mul(getStakingCoinPerSec());
        return reward;
    }

    function totalStakingAmount() public view returns (uint256) {
        return this.pendingCoin().add(totalAmount);
    }

    function myBenefits() public view returns (uint256) {
        if (totalShares == 0) 
            return 0;
        UserInfo storage user = userInfo[msg.sender];
        uint256 computePer = accPerShare.add(divFloor(this.pendingCoin(),lpBalance()));
        uint256 ben = decimalMul(user.amount,computePer);

        if (ben > user.rewardDebt)
            return ben.sub(user.rewardDebt);
        else
            return 0;
    }

    function myValue() public view returns (uint256) {
        uint256 computePer = accPerShare.add(divFloor(this.pendingCoin(),lpBalance()));
        UserInfo storage user = userInfo[msg.sender];
        if(user.shares == 0) return 0;
        return decimalMul(user.amount,computePer).sub(user.rewardDebt).add(user.rewards);
    }

    function sharesPrice() public view returns (uint256) {
        uint256 lpb = lpBalance();
        if (lpb == 0) return 0;
        uint256 computePer = accPerShare.add(divFloor(this.pendingCoin(),lpb));
        return lpb.mul(getEther()).mul(computePer).div(totalShares);
    }

    // function getTime()
    function getTime() public view returns (uint256) {
        return now;
    }

    function getPkBalance() public view returns (uint256) {
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

    function setFeeAddress(address newAddress) public {
        require(msg.sender == owner);
        require(newAddress != address(0), "set to 0");
        require(newAddress != address(0xdead), "set to 0xdead");
        newContractAddress = newAddress;
    }

    function transferLpFee(uint256 amount) public {
        require(msg.sender == owner);
        require(newContractAddress != address(0), "transfer to 0");
        require(totalLpFee >= amount, "not enough");

        lp.transfer(newContractAddress, amount);
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

    function setLp(ILPToken _lp) public {
        if (msg.sender == owner) {
            lp = _lp;
        }
    }
}
