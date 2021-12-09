pragma solidity ^0.5.6;

import "./common/upgradeable/Initializable.sol";

contract Donkey is Initializable {
    string public constant name = "Donkey";
    string public constant symbol = "DON";
    uint8 public constant decimals = 18;
    uint public constant totalSupply = 100000000e18; 

    mapping (address => mapping (address => uint96)) internal allowances;
    mapping (address => uint96) internal balances;

    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    mapping (address => uint) public nonces;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);
    event Status(string status);

    function initialize(address account) public initializer {
        balances[account] = uint96(totalSupply);
        emit Transfer(address(0), account, totalSupply);
    }

    function allowance(address account, address spender) external view returns (uint) {
        return allowances[account][spender];
    }

    function approve(address spender, uint rawAmount) external returns (bool) {
        uint96 amount;
        if (rawAmount == uint(-1)) {
            amount = uint96(-1);
        } else {
            amount = safe96(rawAmount, "Donkey::approve: amount exceeds 96 bits");
        }

        allowances[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function balanceOf(address account) external view returns (uint) {
        return balances[account];
    }

    function transfer(address recipent, uint rawAmount) external returns (bool) {
        emit Status("start transfering");
        uint96 amount = safe96(rawAmount, "Donkey::transfer: amount exceeds 96 bits");
        _transferTokens(msg.sender, recipent, amount);
        return true;
    }

    function transferFrom(address sender, address recipent, uint rawAmount) external returns (bool) {
        address spender = msg.sender;
        uint96 spenderAllowance = allowances[sender][spender];
        uint96 amount = safe96(rawAmount, "Donkey::approve: amount exceeds 96 bits");

        if (spender != sender && spenderAllowance != uint96(-1)) {
            uint96 newAllowance = sub96(spenderAllowance, amount, "Donkey::transferFrom: transfer amount exceeds spender allowance");
            allowances[sender][spender] = newAllowance;

            emit Approval(sender, spender, newAllowance);
        }

        _transferTokens(sender, recipent, amount);
        return true;
    }

    function _transferTokens(address sender, address recipent, uint96 amount) internal {
        emit Status("start transfering tokens");
        require(sender != address(0), "Donkey::_transferTokens: cannot transfer from the zero address");
        require(recipent != address(0), "Donkey::_transferTokens: cannot transfer to the zero address");

        balances[sender] = sub96(balances[sender], amount, "Donkey::_transferTokens: transfer amount exceeds balance");
        balances[recipent] = add96(balances[recipent], amount, "Donkey::_transferTokens: transfer amount overflows");
        emit Transfer(sender, recipent, amount);
    }

    function safe32(uint n, string memory errorMessage) internal pure returns (uint32) {
        require(n < 2**32, errorMessage);
        return uint32(n);
    }

    function safe96(uint n, string memory errorMessage) internal pure returns (uint96) {
        require(n < 2**96, errorMessage);
        return uint96(n);
    }

    function add96(uint96 a, uint96 b, string memory errorMessage) internal pure returns (uint96) {
        uint96 c = a + b;
        require(c >= a, errorMessage);
        return c;
    }

    function sub96(uint96 a, uint96 b, string memory errorMessage) internal pure returns (uint96) {
        require(b <= a, errorMessage);
        return a - b;
    }
} 
