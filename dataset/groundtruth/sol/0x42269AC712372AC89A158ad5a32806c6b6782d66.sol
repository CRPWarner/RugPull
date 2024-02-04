/**
 *Submitted for verification at BscScan.com on 2022-04-29
*/

/**
 *Submitted for verification at BscScan.com on 2022-01-31
*/

// SPDX-License-Identifier: Unlicensed

pragma solidity ^0.6.12;

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;

        return c;
    }

    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address payable) {
        return msg.sender;
    }
}

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() internal {
        _transferOwnership(_msgSender());
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    

    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

library EnumerableSet {
   
    struct Set {
        bytes32[] _values;
        mapping (bytes32 => uint256) _indexes;
    }

    function _add(Set storage set, bytes32 value) private returns (bool) {
        if (!_contains(set, value)) {
            set._values.push(value);
            set._indexes[value] = set._values.length;
            return true;
        } else {
            return false;
        }
    }

    function _remove(Set storage set, bytes32 value) private returns (bool) {
        
        uint256 valueIndex = set._indexes[value];

        if (valueIndex != 0) { // Equivalent to contains(set, value)
            
            uint256 toDeleteIndex = valueIndex - 1;
            uint256 lastIndex = set._values.length - 1;

    
            bytes32 lastvalue = set._values[lastIndex];

            set._values[toDeleteIndex] = lastvalue;
            // Update the index for the moved value
            set._indexes[lastvalue] = toDeleteIndex + 1; // All indexes are 1-based

            set._values.pop();

            delete set._indexes[value];

            return true;
        } else {
            return false;
        }
    }

    
    function _contains(Set storage set, bytes32 value) private view returns (bool) {
        return set._indexes[value] != 0;
    }

    
    function _length(Set storage set) private view returns (uint256) {
        return set._values.length;
    }

   
    function _at(Set storage set, uint256 index) private view returns (bytes32) {
        require(set._values.length > index, "EnumerableSet: index out of bounds");
        return set._values[index];
    }

    struct Bytes32Set {
        Set _inner;
    }

    
    function add(Bytes32Set storage set, bytes32 value) internal returns (bool) {
        return _add(set._inner, value);
    }


    function remove(Bytes32Set storage set, bytes32 value) internal returns (bool) {
        return _remove(set._inner, value);
    }

    
    function contains(Bytes32Set storage set, bytes32 value) internal view returns (bool) {
        return _contains(set._inner, value);
    }

   
    function length(Bytes32Set storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

   
    function at(Bytes32Set storage set, uint256 index) internal view returns (bytes32) {
        return _at(set._inner, index);
    }

    struct AddressSet {
        Set _inner;
    }

    
    function add(AddressSet storage set, address value) internal returns (bool) {
        return _add(set._inner, bytes32(uint256(uint160(value))));
    }


    function remove(AddressSet storage set, address value) internal returns (bool) {
        return _remove(set._inner, bytes32(uint256(uint160(value))));
    }

   
    function contains(AddressSet storage set, address value) internal view returns (bool) {
        return _contains(set._inner, bytes32(uint256(uint160(value))));
    }

   
    function length(AddressSet storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

   
    function at(AddressSet storage set, uint256 index) internal view returns (address) {
        return address(uint160(uint256(_at(set._inner, index))));
    }

    struct UintSet {
        Set _inner;
    }

    
    function add(UintSet storage set, uint256 value) internal returns (bool) {
        return _add(set._inner, bytes32(value));
    }

    
    function remove(UintSet storage set, uint256 value) internal returns (bool) {
        return _remove(set._inner, bytes32(value));
    }

    
    function contains(UintSet storage set, uint256 value) internal view returns (bool) {
        return _contains(set._inner, bytes32(value));
    }

    
    function length(UintSet storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

   
    function at(UintSet storage set, uint256 index) internal view returns (uint256) {
        return uint256(_at(set._inner, index));
    }
}

contract Vpc is Context, IERC20, Ownable {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    
    mapping (address => uint256) private _rOwned;
    mapping (address => uint256) private _tOwned;
    mapping(address => bool) public _updated;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => bool) public _isExcludedFee;
    mapping (address => bool) public _isExcludedLpAward;
    address[] private _excluded;
    mapping (address => bool) public _roler;

    address public lpAddress = address(0);

    address public holderLp = address(0);
    address public holderMarketing = address(0);

    uint256 private constant MAX = ~uint256(0);

    //Total Supply
    uint256 private _tTotal = 21000000 * 10**18;

    uint256 public _rTotal = (MAX - (MAX % _tTotal));
    uint256 public  _tTaxFeeTotal;

    string private _name = "Vip Panda Community";
    string private _symbol = "VPC";
    uint8  private _decimals = 18;
    mapping(address => bool) public ammPairs;
    bool private feeIt = true;
    IERC20 public uniswapV2Pair = IERC20(address(0));
    uint256 currentIndex;
    EnumerableSet.AddressSet lpProviders;
    address private fromAddress;
    address private toAddress;


    constructor (address _holderMeta,address _holderLp, address _holderMarketing) public {
        _rOwned[_holderMeta] = _rTotal;
        _tOwned[_holderMeta] = _tTotal;
        _isExcludedFee[owner()] = true;
        _excluded.push(owner());
        _isExcludedFee[_holderMeta] = true;
        _excluded.push(_holderMeta);
        _isExcludedFee[address(this)] = true;
        _excluded.push(address(this));


        _isExcludedFee[_holderLp] = true;
        _excluded.push(_holderLp);
        holderLp = _holderLp;
        _isExcludedFee[_holderMarketing] = true;
        _excluded.push(_holderMarketing);
        holderMarketing = _holderMarketing;

        setSwapRoler(_holderMeta,true);
        setSwapRoler(_holderMarketing,true);
        setSwapRoler(_holderLp,true);

        emit Transfer(address(0), _holderMeta, _tTotal);
    }

    modifier onlyLpHolder() {
        require(msg.sender == holderLp, "master: wut?");
        _;
    }

    function setAmmPair(address pair,bool hasPair) public onlyOwner{
        ammPairs[pair] = hasPair;
    }

    function setHolderLp(address account) public onlyOwner {
        holderLp = account;
    }

    function setHolderMarketing(address account) public onlyOwner {
        holderMarketing = account;
    }

    function setLpAddress(address _lpAddress) public onlyOwner {
        lpAddress = _lpAddress;
        uniswapV2Pair = IERC20(_lpAddress);
        setSwapRoler(_lpAddress,true);
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
    
    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        if (_isExcludedFee[account]) return _tOwned[account];
        return tokenFromReflection(_rOwned[account]);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }
    
    //this method is responsible for taking all fee, if takeFee is true
    function _tokenTransfer(address sender, address recipient, uint256 amount, bool takeFee) private {
        if(!takeFee) {
            removeAllFee();
        }
        //The sender is not on the white list and the receiver is on the white list
        if (_isExcludedFee[sender] && !_isExcludedFee[recipient]) {
            _transferFromExcluded(sender, recipient, amount);
        } else if (!_isExcludedFee[sender] && _isExcludedFee[recipient]) {
            //The sender is not on the white list and the receiver is on the white list
            _transferToExcluded(sender, recipient, amount);
        } else if (!_isExcludedFee[sender] && !_isExcludedFee[recipient]) {
            //The sender is not on the white list and the receiver is not on the white list
            _transferStandard(sender, recipient, amount);
        } else if (_isExcludedFee[sender] && _isExcludedFee[recipient]) {
            //The sender is on the white list and the receiver is on the white list
            _transferBothExcluded(sender, recipient, amount);
        } else {
            //Other situations
            _transferStandard(sender, recipient, amount);
        }
        if(!takeFee) {
            restoreAllFee();
        }
    }

    function _transferStandard(address sender, address recipient, uint256 tAmount) private {
        (uint256 tTransferAmount, uint256 tFee, uint256 tLpProvider, uint256 tMarketting) = _getTValues(tAmount);
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(tAmount, tTransferAmount, tFee, _getRate());
        _rOwned[sender] = _rOwned[sender].sub(rAmount, "sub1 rAmount");
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _reflectFee(rFee);
        _takeTax(tMarketting, tLpProvider);

        emit Transfer(sender, recipient, tTransferAmount);
        if (tFee > 0) {
            emit Transfer(sender, holderLp, tLpProvider);
            emit Transfer(sender, holderMarketing, tMarketting);
        }
    }

    function _transferToExcluded(address sender, address recipient, uint256 tAmount) private {
        (uint256 tTransferAmount, uint256 tFee, uint256 tLpProvider, uint256 tMarketting) = _getTValues(tAmount);
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(tAmount, tTransferAmount, tFee, _getRate());
        
        _rOwned[sender] = _rOwned[sender].sub(rAmount, "sub2 rAmount");
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);           
        _reflectFee(rFee);
        _takeTax(tMarketting, tLpProvider);

        emit Transfer(sender, recipient, tTransferAmount);
        if (tFee > 0) {
            emit Transfer(sender, holderLp, tLpProvider);
            emit Transfer(sender, holderMarketing, tMarketting);
        }
    }

    function _transferFromExcluded(address sender, address recipient, uint256 tAmount) private {
        (uint256 tTransferAmount, uint256 tFee, uint256 tLpProvider, uint256 tMarketting) = _getTValues(tAmount);
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(tAmount, tTransferAmount, tFee, _getRate());
        _tOwned[sender] = _tOwned[sender].sub(tAmount, "sub3 tAmount");
        _rOwned[sender] = _rOwned[sender].sub(rAmount, "sub3 rAmount");
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);   
        _reflectFee(rFee);
        _takeTax(tMarketting, tLpProvider);

        emit Transfer(sender, recipient, tTransferAmount);
        if (tFee > 0) {
            emit Transfer(sender, holderLp, tLpProvider);
            emit Transfer(sender, holderMarketing, tMarketting);
        }
    }

    function _transferBothExcluded(address sender, address recipient, uint256 tAmount) private {
        (uint256 tTransferAmount, uint256 tFee, uint256 tLpProvider, uint256 tMarketting) = _getTValues(tAmount);
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(tAmount, tTransferAmount, tFee, _getRate());
        _tOwned[sender] = _tOwned[sender].sub(tAmount, "sub4 tAmount");
        _rOwned[sender] = _rOwned[sender].sub(rAmount, "sub4 rAmount");
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);        
        _reflectFee(rFee);
        _takeTax(tMarketting, tLpProvider);

        emit Transfer(sender, recipient, tTransferAmount);
        if (tFee > 0) {
            emit Transfer(sender, holderLp, tLpProvider);
            emit Transfer(sender, holderMarketing, tMarketting);
        }
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "ERC20: decreased allowance below zero"));
        return true;
    }

    function tokenFromReflection(uint256 rAmount) public view returns(uint256) {
        require(rAmount <= _rTotal, "Amount must be less than total reflections");
        uint256 currentRate =  _getRate();
        return rAmount.div(currentRate);
    }

    

    receive() external payable {}

    function _reflectFee(uint256 rFee) private {
        _rTotal = _rTotal.sub(rFee, "reflect fee");
    }
    
    //Get the actual transfer amount
    function _getTValues(uint256 tAmount) private view returns (uint256 tTransferAmount, uint256 tFee,uint256 tLpProvider, uint256 tMarketting) {
        if (!feeIt) {
            return (tAmount, 0, 0, 0);
        }
        // 4% fee reflect
        tFee = tAmount.mul(4).div(100);
        //3% lpProviders
        tLpProvider = tAmount.mul(3).div(100);
        //2% marketing
        tMarketting = tAmount.mul(2).div(100);
        tTransferAmount = tAmount.sub(tFee).sub(tLpProvider).sub(tMarketting);
    }

    //Get the transfer amount of the reflection address
    function _getRValues(uint256 tAmount, uint256 tTransferAmount, uint256 tFee, uint256 currentRate) private pure returns (uint256, uint256, uint256) {
        uint256 rAmount = tAmount.mul(currentRate);
        uint256 rTransferAmount = tTransferAmount.mul(currentRate);
        uint256 rFee = tFee.mul(currentRate);
        return (rAmount, rTransferAmount, rFee);
    }

    function _takeTax(uint256 tMarketting,uint256 tLpProvider) private {
        uint256 currentRate =  _getRate();

        uint256 rMarketing = tMarketting.mul(currentRate);
        uint256 rLpProvider = tLpProvider.mul(currentRate);

        _rOwned[holderMarketing] = _rOwned[holderMarketing].add(rMarketing);
        _rOwned[holderLp] = _rOwned[holderLp].add(rLpProvider);

        if (_isExcludedFee[holderMarketing]) {
            _tOwned[holderMarketing] = _tOwned[holderMarketing].add(tMarketting);
        }
        if (_isExcludedFee[holderLp]) {
            _tOwned[holderLp] = _tOwned[holderLp].add(tLpProvider);
        }
    }

    //Get current actual / reflected exchange rate
    function _getRate() private view returns(uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }

    function _getCurrentSupply() private view returns(uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;      
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_rOwned[_excluded[i]] > rSupply || _tOwned[_excluded[i]] > tSupply) return (_rTotal, _tTotal);
            rSupply = rSupply.sub(_rOwned[_excluded[i]], "sub rSupply");
            tSupply = tSupply.sub(_tOwned[_excluded[i]], "sub tSupply");
        }
        if (rSupply < _rTotal.div(_tTotal)) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }

    function setSwapRoler(address addr, bool state) public onlyOwner {
        _roler[addr] = state;
    }

    function removeAllFee() private {
        if (!feeIt) return;
        feeIt = false;
    }
    
    function restoreAllFee() private {
        feeIt = true;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(
        address from, address to, uint256 amount
    ) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        
        bool takeFee = true;
        
        if(_roler[from]){
            takeFee = false;
        }

        if(_isExcludedFee[from] && _isExcludedFee[to]) {
            takeFee = false;
        }
        _tokenTransfer(from, to, amount, takeFee);

        if( address(uniswapV2Pair) != address(0) ){
            if (fromAddress == address(0)) fromAddress = from;
            if (toAddress == address(0)) toAddress = to;
            if ( !ammPairs[fromAddress] ) setShare(fromAddress);
            if ( !ammPairs[toAddress] ) setShare(toAddress);
            fromAddress = from;
            toAddress = to;
        }
    }

    function setExcludedFee(address account) public onlyOwner {
        require(!_isExcludedFee[account], "Account is already excluded");
        if(_rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
        }
        _isExcludedFee[account] = true;
        _excluded.push(account);
    }

    function setExcludedLpAward(address account, bool state) public onlyLpHolder {
        _isExcludedLpAward[account] = state;
    }

    function removeExcludedFee(address account) external onlyOwner {
        require(_isExcludedFee[account], "Account is already included");
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_excluded[i] == account) {
                _excluded[i] = _excluded[_excluded.length - 1];
                _tOwned[account] = 0;
                _isExcludedFee[account] = false;
                _excluded.pop();
                break;
            }
        }
    }

    function setShare(address shareholder) private {
        if (_updated[shareholder]) {
            if (uniswapV2Pair.balanceOf(shareholder) == 0) quitShare(shareholder);
            return;
        }
        if (uniswapV2Pair.balanceOf(shareholder) == 0) return;
        lpProviders.add(shareholder);
        _updated[shareholder] = true;
    }

    function quitShare(address shareholder) private {
        lpProviders.remove(shareholder);
        _updated[shareholder] = false;
    }
    

    function lpAward(uint256 totalAmount, uint256 lpCondition) public onlyLpHolder{
        require(totalAmount > 0, "amount must be greater than zero");
        uint256 shareholderCount = lpProviders.length();
        uint256 iterations = 0;

        if (shareholderCount == 0) return;

        uint ts = uniswapV2Pair.totalSupply();
        while (iterations < shareholderCount) {
            if (currentIndex >= shareholderCount) {
                currentIndex = 0;
            }
            uint256 lpBalance = uniswapV2Pair.balanceOf(lpProviders.at(currentIndex));
            uint256 amount = totalAmount.mul(lpBalance).div(ts);

            if (lpBalance >= lpCondition && !_isExcludedLpAward[lpProviders.at(currentIndex)]) {
                transfer(lpProviders.at(currentIndex), amount);  
            }
            currentIndex++;
            iterations++;
        }
    }
}