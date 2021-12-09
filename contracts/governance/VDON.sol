pragma solidity ^0.5.6;

import "../common/upgradeable/Initializable.sol";

contract VDON is Initializable {

  event Mint(address minter, address stakingContract, uint256 amount);
  event Burn(address burner, address stakingContract, uint256 amount);

  mapping(address => bool) public whiteList;
  mapping(address => uint256) private _balances;

  uint256 private _totalSupply;

  string private _name;
  string private _symbol;
  uint8 private _decimals;

  bool public isMintPaused;
  bool public isBurnPaused;

  address public admin;

  function initialize(string memory name_, string memory symbol_, uint8 decimals_) public initializer {
    admin = msg.sender;
    _name = name_;
    _symbol = symbol_;
    _decimals = decimals_;
  }

  function name() public view returns (string memory) {
    return _name;
  }

  function symbol() public view returns (string memory) {
    return _symbol;
  }

  function decimals() public view returns (uint8) {
    return _decimals;
  }

  function totalSupply() public view returns (uint256) {
    return _totalSupply;
  }

  function balanceOf(address account) public view returns (uint256) {
    return _balances[account];
  }
  
  function mint(address account, uint amount) public {
    require(whiteList[msg.sender] == true || msg.sender == admin, "E1");
    require(!isMintPaused, "E110");
    _balances[account] += amount;
    _totalSupply += amount;
    emit Mint(account, msg.sender, amount);
  }

  function burn(address account, uint amount) public {
    require(whiteList[msg.sender] == true || msg.sender == admin, "E1");
    require(!isBurnPaused, "E111");
    uint256 accountBalance = _balances[account];
    require(accountBalance >= amount, "E104");
    _balances[account] = accountBalance - amount;
    _totalSupply -= amount;
    emit Burn(account, msg.sender, amount);
  }

  function burnMax(address account) public {
    require(whiteList[msg.sender] || msg.sender == admin, "E1");
    require(!isBurnPaused, "E111");
    uint256 accountBalance = _balances[account];
    _balances[account] = 0;
    _totalSupply -= accountBalance;
    emit Burn(account, msg.sender, accountBalance);
  }
  
  function setWhiteList(address account, bool isWhiteList) external {
    require(msg.sender == admin);
    whiteList[account] = isWhiteList;
  }
}
