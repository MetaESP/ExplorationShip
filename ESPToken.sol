// SPDX-License-Identifier: Unlicensed
// just use in bsc or bsc testnet
// before deploy, modify line 57 pair address, it can be the usdt address
// before deploy, modify line 53 IPancakeswapV2Router02 to mainnet
// before deploy, modify line 65 _balances[_msgSender()]
// after deploy, need to set gamePool

pragma solidity ^0.8.0;

import "./token-lib/IBEP20.sol";
import "./token-lib/SafeMath.sol";
import "./token-lib/Context.sol";
import "./token-lib/Ownable.sol";
import "./token-lib/IPancakeswapV2Factory.sol";
import "./token-lib/IPancakeswapV2Router02.sol";

contract EspToken is Context, IBEP20, Ownable {
    using SafeMath for uint256;
    
    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;

    mapping (address => bool) private _isExcludedFromFee;

    address public gamePool;
    
    uint256 private _tTotal = 50000000 * 10**18;
    uint256 private constant MAX = ~uint256(0);
    string private _name = "ExploShipToken";
    string private _symbol = "ESP";
    uint8 private _decimals = 18;
    
    uint256 public _taxFee = 5; 
    uint256 private _previousTaxFee = _taxFee;

    IPancakeswapV2Router02 public pancakeswapV2Router;
    address public pancakeswapV2Pair;

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiquidity
    );
    event ExcludedFromFee(address account);
    event IncludedToFee(address account);
    event UpdateFees(uint256 taxFee);
    event UpdatedMaxTxAmount(uint256 maxTxAmount);
    event UpdateGamePoolAddress(address account);
    event UpdatedCoolDowntime(uint256 timeForContract);
    
    constructor () {
        //Test Net
        IPancakeswapV2Router02 _pancakeswapV2Router = IPancakeswapV2Router02(0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3);
        //Mian Net
        // IPancakeswapV2Router02 _pancakeswapV2Router = IPancakeswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
        pancakeswapV2Pair = IPancakeswapV2Factory(_pancakeswapV2Router.factory())
            .createPair(address(this),_pancakeswapV2Router.WETH()); // this weth definite in v2routerOnTestnet, mean wbnb

        // set the rest of the contract variables
        pancakeswapV2Router = _pancakeswapV2Router;
        
        //exclude owner and this contract from fee
        _isExcludedFromFee[_msgSender()] = true;
        _isExcludedFromFee[address(this)] = true;
        _balances[_msgSender()] = _tTotal;    //modify
        emit Transfer(address(0), owner(), _tTotal);
    }
    
    function symbol() external view override returns (string memory) {
        return _symbol;
    }

    function name() external view override returns (string memory) {
        return _name;
    }
    
    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function totalSupply() external view override returns (uint256) {
        return _tTotal;
    }
    
    function getOwner() external view override returns (address) {
        return owner();
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }
    
    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "BEP20: transfer amount exceeds allowance"));
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "BEP20: decreased allowance below zero"));
        return true;
    }

    function setGamePoolAddress(address account) external onlyOwner {
        require(account != gamePool, "This address was already used");
        gamePool = account;
        emit UpdateGamePoolAddress(account);
    }
    
    function excludeFromFee(address account) external onlyOwner {
        _isExcludedFromFee[account] = true;
        emit ExcludedFromFee(account);
    }
    
    function includeInFee(address account) external onlyOwner {
        _isExcludedFromFee[account] = false;
        emit IncludedToFee(account);
    }

    function setFees(uint256 taxFee) external onlyOwner() {
        require(_taxFee != taxFee);
        _taxFee = taxFee;
        emit UpdateFees(taxFee);
    }
    
     //to receive ETH from pancakeswapV2Router when swapping
    receive() external payable {}

    function _getFeeValues(uint256 tAmount) private view returns (uint256) {
        uint256 fee = tAmount.mul(_taxFee).div(10**2);
        uint256 tTransferAmount = tAmount.sub(fee);
        return tTransferAmount;
    }

    function removeAllFee() private {
        if(_taxFee == 0 ) return;
        _previousTaxFee = _taxFee;
        _taxFee = 0;
    }
    
    function restoreAllFee() private {
        _taxFee = _previousTaxFee;
    }
    
    function isExcludedFromFee(address account) external view returns(bool) {
        return _isExcludedFromFee[account];
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "BEP20: approve from the zero address");
        require(spender != address(0), "BEP20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private {
        require(from != address(0), "BEP20: transfer from the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        
        //indicates if fee should be deducted from transfer
        bool takeFee = false;
        if (balanceOf(pancakeswapV2Pair) > 0 && (to == pancakeswapV2Pair)) {  //just sell the token need to pay tax   || from == pancakeswapV2Pair
            takeFee = true;
        }
        
        //if any account belongs to _isExcludedFromFee account then remove the fee
        if (_isExcludedFromFee[from] || _isExcludedFromFee[to]){
            takeFee = false;
        }
        
        //transfer amount, it will take tax, burn, liquidity fee
        _tokenTransfer(from,to,amount,takeFee);
    }

    //this method is responsible for taking all fee, if takeFee is true
    function _tokenTransfer(address sender, address recipient, uint256 amount, bool takeFee) private {
        if(!takeFee)
            removeAllFee();
        uint256 tTransferAmount = _getFeeValues(amount);
        _balances[sender] = _balances[sender].sub(amount);
        _balances[recipient] = _balances[recipient].add(tTransferAmount);   
        _balances[gamePool] = _balances[gamePool].add(amount.sub(tTransferAmount));
        emit Transfer(sender, recipient, tTransferAmount);
        
        if(!takeFee)
            restoreAllFee();
    }

}

