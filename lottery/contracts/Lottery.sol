pragma solidity ^0.4.24;

library SafeMath {

  /**
  * @dev Multiplies two numbers, throws on overflow.
  */
  function mul(uint256 _a, uint256 _b) internal pure returns (uint256 c) {
    // Gas optimization: this is cheaper than asserting 'a' not being zero, but the
    // benefit is lost if 'b' is also tested.
    // See: https://github.com/OpenZeppelin/openzeppelin-solidity/pull/522
    if (_a == 0) {
      return 0;
    }

    c = _a * _b;
    assert(c / _a == _b);
    return c;
  }

  /**
  * @dev Integer division of two numbers, truncating the quotient.
  */
  function div(uint256 _a, uint256 _b) internal pure returns (uint256) {
    // assert(_b > 0); // Solidity automatically throws when dividing by 0
    // uint256 c = _a / _b;
    // assert(_a == _b * c + _a % _b); // There is no case in which this doesn't hold
    return _a / _b;
  }

  /**
  * @dev Subtracts two numbers, throws on overflow (i.e. if subtrahend is greater than minuend).
  */
  function sub(uint256 _a, uint256 _b) internal pure returns (uint256) {
    assert(_b <= _a);
    return _a - _b;
  }

  /**
  * @dev Adds two numbers, throws on overflow.
  */
  function add(uint256 _a, uint256 _b) internal pure returns (uint256 c) {
    c = _a + _b;
    assert(c >= _a);
    return c;
  }
}

contract Lottery {
    using SafeMath for uint256;

    uint256 constant public ONE_HUNDRED_PERCENTS = 10000;               // 100%
    uint256[] public DAILY_INTEREST = [111, 222, 333, 444];             // 1.11%, 2.22%, 3.33%, 4.44%
    uint256 public MARKETING__AND_TEAM_FEE = 1000;                      // 10%
    uint256 public referralPercents = 1000;                             // 10%
    uint256 constant public MAX_USER_DEPOSITS_COUNT = 50;               // 50 times
    uint256 constant public MAX_DIVIDEND_RATE = 25000;                  // 250%
    uint256 constant public MINIMUM_DEPOSIT = 100 finney;               // 0.1 eth
    uint256 public wave = 0;

    struct Deposit {
        uint256 amount;
        uint256 interest;
        uint256 withdrawedRate;
    }

    struct User {
        address referrer;
        uint256 referralAmount;
        uint256 firstTime;
        uint256 lastPayment;
        Deposit[] deposits;
        uint256 referBonus;
    }

    address public marketingAndTeam = 0x1111111111111111111111111111111111111111; // need to change
    address public owner = 0x1111111111111111111111111111111111111111;
    bool public running = true;
    mapping(uint256 => mapping(address => User)) public users;

    event InvestorAdded(address indexed investor);
    event ReferrerAdded(address indexed investor, address indexed referrer);
    event DepositAdded(address indexed investor, uint256 indexed depositsCount, uint256 amount);
    event UserDividendPayed(address indexed investor, uint256 dividend);
    event DepositDividendPayed(address indexed investor, uint256 indexed index, uint256 deposit, uint256 totalPayed, uint256 dividend);
    event FeePayed(address indexed investor, uint256 amount);
    event BalanceChanged(uint256 balance);
    
    function() public payable {
        
        // Dividends
        withdrawDividends();

        // Deposit
        if(msg.value > 0) doInvest();
        
        emit BalanceChanged(address(this).balance);
        
        // Reset
        if (address(this).balance == 0) {
            wave = wave.add(1);
            running = true;
        }
    }
        
    function withdrawDividends() internal {
        User storage user = users[wave][msg.sender];
        
        uint256 dividendsSum;
        for (uint i = 0; i < user.deposits.length; i++) {
            uint256 withdrawRate = dividendRate(msg.sender, i);
            user.deposits[i].withdrawedRate = user.deposits[i].withdrawedRate.add(withdrawRate);
            dividendsSum = dividendsSum.add(withdrawRate.div(ONE_HUNDRED_PERCENTS).div(1 days));
            emit DepositDividendPayed(
                msg.sender,
                i,
                user.deposits[i].amount,
                user.deposits[i].withdrawedRate.div(ONE_HUNDRED_PERCENTS).div(1 days),
                withdrawRate.div(ONE_HUNDRED_PERCENTS).div(1 days)
            );
        }
        dividendsSum = dividendsSum.add(user.referBonus);
        
        if (dividendsSum > 0) {
            user.referBonus = 0;
            user.lastPayment = now;
            msg.sender.transfer(min(dividendsSum, address(this).balance));
            emit UserDividendPayed(msg.sender, dividendsSum);
        }
    }

    function doInvest() internal {
        User storage user = users[wave][msg.sender];
        if (msg.value < MINIMUM_DEPOSIT) {
            if (msg.value > 0) msg.sender.transfer(msg.value);
        } else {
            if (user.firstTime == 0) {
                user.firstTime = now;
                user.lastPayment = now;
                emit InvestorAdded(msg.sender);
            }
            
            // Create deposit
            user.deposits.push(Deposit({
                amount: msg.value,
                interest: getUserInterest(msg.sender),
                withdrawedRate: 0
            }));
            require(user.deposits.length <= MAX_USER_DEPOSITS_COUNT, "Too many deposits per user");
            emit DepositAdded(msg.sender, user.deposits.length, msg.value);

            // Add referral if possible
            if (user.referrer == address(0) && msg.data.length == 20) {
                address newReferrer = _bytesToAddress(msg.data);
                if (newReferrer != address(0) && newReferrer != msg.sender && users[wave][newReferrer].firstTime > 0) {
                    user.referrer = newReferrer;
                    users[wave][newReferrer].referralAmount += 1;
                    emit ReferrerAdded(msg.sender, newReferrer);
                }
            }
            
            // Referrers fees
            if (user.referrer != address(0)) {
                uint256 refAmount = msg.value.mul(referralPercents).div(ONE_HUNDRED_PERCENTS);
                users[wave][user.referrer].referBonus = users[wave][user.referrer].referBonus.add(refAmount);
            }

            // Marketing and Team fee
            uint256 marketingAndTeamFee = msg.value.mul(MARKETING__AND_TEAM_FEE).div(ONE_HUNDRED_PERCENTS);
            marketingAndTeam.transfer(marketingAndTeamFee); // solium-disable-line security/no-send
            emit FeePayed(msg.sender, marketingAndTeamFee);
        }

    }
    
    function getUserInterest(address wallet) public view returns (uint256) {
        User storage user = users[wave][wallet];
        if (user.referralAmount == 0) {
            return DAILY_INTEREST[0];
        } else if (user.referralAmount == 1) {
            return DAILY_INTEREST[1];
        } else if (user.referralAmount == 2) {
            return DAILY_INTEREST[2];
        } else {
            return DAILY_INTEREST[3];
        }
    }

    function _bytesToAddress(bytes data) private pure returns(address addr) {
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            addr := mload(add(data, 20)) 
        }
    }
    
    function min(uint256 a, uint256 b) internal pure returns(uint256) {
        if(a < b) return a;
        return b;
    }

    function dividendRate(address wallet, uint256 index) internal view returns(uint256 rate) {
        User memory user = users[wave][wallet];
        uint256 duration = now.sub(user.lastPayment);
        rate = user.deposits[index].interest.mul(duration);
        uint256 leftRate = MAX_DIVIDEND_RATE.sub(user.deposits[index].withdrawedRate);
        rate = min(rate, leftRate);
    }
    
    function dividendsSumForUser(address wallet) external view returns(uint256 dividendsSum) {
        User memory user = users[wave][wallet];
        for (uint i = 0; i < user.deposits.length; i++) {
            uint256 withdrawRate = dividendRate(wallet, i);
            dividendsSum = dividendsSum.add(withdrawRate.div(ONE_HUNDRED_PERCENTS).div(1 days));
        }
        dividendsSum = min(dividendsSum, address(this).balance);
    }
    
    function changeInterest(uint256[] interestList) external {
        require(address(msg.sender) == owner);
        DAILY_INTEREST = interestList;
    }
    
    function changeTeamFee(uint256 feeRate) external {
        require(address(msg.sender) == owner);
        MARKETING__AND_TEAM_FEE = feeRate;
    }
}