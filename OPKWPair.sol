// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;
contract OPKWPair {
    string public name = "OPKW Pair";
    string public symbol = "OPKW-LP";
    uint8 public decimals = 18;
    uint public totalSupply;
    mapping(address => uint) public balanceOf;
    mapping(address => mapping(address => uint)) public allowance;
    address public factory;
    address public token0;
    address public token1;
    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;
    uint public price0CumulativeLast;
    uint public price1CumulativeLast;
    uint public kLast;
    uint private unlocked = 1;
    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(address indexed owner, address indexed spender, uint value);
    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(address indexed sender, uint amount0In, uint amount1In, uint amount0Out, uint amount1Out, address indexed to);
    event Sync(uint112 reserve0, uint112 reserve1);
    modifier lock() { require(unlocked == 1, "LOCKED"); unlocked = 0; _; unlocked = 1; }
    constructor() { factory = msg.sender; }
    function initialize(address _token0, address _token1) external {
        require(msg.sender == factory, "FORBIDDEN");
        token0 = _token0; token1 = _token1;
    }
    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0; _reserve1 = reserve1; _blockTimestampLast = blockTimestampLast;
    }
    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSignature("transfer(address,uint256)", to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FAILED");
    }
    function _update(uint balance0, uint balance1, uint112 _reserve0, uint112 _reserve1) private {
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast;
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            price0CumulativeLast += uint(uint224(_reserve1) * 2**112 / _reserve0) * timeElapsed;
            price1CumulativeLast += uint(uint224(_reserve0) * 2**112 / _reserve1) * timeElapsed;
        }
        reserve0 = uint112(balance0); reserve1 = uint112(balance1); blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }
    function _mint(address to, uint value) private {
        totalSupply += value; balanceOf[to] += value; emit Transfer(address(0), to, value);
    }
    function _burn(address from, uint value) private {
        balanceOf[from] -= value; totalSupply -= value; emit Transfer(from, address(0), value);
    }
    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
        address feeTo = IOPKWFactory(factory).feeTo();
        feeOn = feeTo != address(0);
        uint _kLast = kLast;
        if (feeOn) {
            if (_kLast != 0) {
                uint rootK = _sqrt(uint(_reserve0) * _reserve1);
                uint rootKLast = _sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint numerator = totalSupply * (rootK - rootKLast);
                    uint denominator = rootK * 5 + rootKLast;
                    uint liquidity = numerator / denominator;
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) { kLast = 0; }
    }
    function _sqrt(uint y) private pure returns (uint z) {
        if (y > 3) { z = y; uint x = y / 2 + 1; while (x < z) { z = x; x = (y / x + x) / 2; } } else if (y != 0) { z = 1; }
    }
    function mint(address to) external lock returns (uint liquidity) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        uint amount0 = balance0 - _reserve0; uint amount1 = balance1 - _reserve1;
        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply;
        if (_totalSupply == 0) { liquidity = _sqrt(amount0 * amount1) - 1000; _mint(address(0), 1000); } else { liquidity = _min(amount0 * _totalSupply / _reserve0, amount1 * _totalSupply / _reserve1); }
        require(liquidity > 0, "INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);
        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint(reserve0) * reserve1;
        emit Mint(msg.sender, amount0, amount1);
    }
    function burn(address to) external lock returns (uint amount0, uint amount1) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        address _token0 = token0; address _token1 = token1;
        uint balance0 = IERC20(_token0).balanceOf(address(this));
        uint balance1 = IERC20(_token1).balanceOf(address(this));
        uint liquidity = balanceOf[address(this)];
        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply;
        amount0 = liquidity * balance0 / _totalSupply;
        amount1 = liquidity * balance1 / _totalSupply;
        require(amount0 > 0 && amount1 > 0, "INSUFFICIENT_LIQUIDITY_BURNED");
        _burn(address(this), liquidity);
        _safeTransfer(_token0, to, amount0);
        _safeTransfer(_token1, to, amount1);
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));
        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint(reserve0) * reserve1;
        emit Burn(msg.sender, amount0, amount1, to);
    }
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external lock {
        require(amount0Out > 0 || amount1Out > 0, "INSUFFICIENT_OUTPUT");
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        require(amount0Out < _reserve0 && amount1Out < _reserve1, "INSUFFICIENT_LIQUIDITY");
        uint balance0; uint balance1;
        { address _token0 = token0; address _token1 = token1; require(to != _token0 && to != _token1, "INVALID_TO"); if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out); if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out); if (data.length > 0) IFlashCallee(to).flashCall(msg.sender, amount0Out, amount1Out, data); balance0 = IERC20(_token0).balanceOf(address(this)); balance1 = IERC20(_token1).balanceOf(address(this)); }
        uint amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, "INSUFFICIENT_INPUT");
        { uint balance0Adjusted = balance0 * 1000 - amount0In * 3; uint balance1Adjusted = balance1 * 1000 - amount1In * 3; require(balance0Adjusted * balance1Adjusted >= uint(_reserve0) * _reserve1 * 1000**2, "K"); }
        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }
    function skim(address to) external lock {
        require(msg.sender == factory || msg.sender == IOPKWFactory(factory).feeToSetter(), "FORBIDDEN");
        address _token0 = token0; address _token1 = token1;
        _safeTransfer(_token0, to, IERC20(_token0).balanceOf(address(this)) - reserve0);
        _safeTransfer(_token1, to, IERC20(_token1).balanceOf(address(this)) - reserve1);
    }
    function sync() external lock { _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reserve0, reserve1); }
    function transfer(address dst, uint wad) public returns (bool) { return transferFrom(msg.sender, dst, wad); }
    function transferFrom(address src, address dst, uint wad) public returns (bool) {
        require(balanceOf[src] >= wad);
        if (src != msg.sender && allowance[src][msg.sender] != type(uint).max) { require(allowance[src][msg.sender] >= wad); allowance[src][msg.sender] -= wad; }
        balanceOf[src] -= wad; balanceOf[dst] += wad; emit Transfer(src, dst, wad); return true;
    }
    function approve(address guy, uint wad) public returns (bool) { allowance[msg.sender][guy] = wad; emit Approval(msg.sender, guy, wad); return true; }
    function _min(uint a, uint b) private pure returns (uint) { return a < b ? a : b; }
}
interface IERC20 { function balanceOf(address o) external view returns (uint); }
interface IOPKWFactory { function feeTo() external view returns (address); function feeToSetter() external view returns (address); }
interface IFlashCallee { function flashCall(address sender, uint amount0, uint amount1, bytes calldata data) external; }
