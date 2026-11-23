// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;
import "./OPKWFactory.sol";
import "./OPKWPair.sol";
import "./WOPKW.sol";
contract OPKWRouter {
    address public factory;
    address payable public WETH;
    modifier ensure(uint deadline) { require(deadline >= block.timestamp, "EXPIRED"); _; }
    constructor(address _factory, address payable _WETH) { factory = _factory; WETH = _WETH; }
    receive() external payable { require(msg.sender == WETH, "NOT_WETH"); }
    function _safeTransfer(address token, address to, uint value) private {
        (bool s, bytes memory d) = token.call(abi.encodeWithSignature("transfer(address,uint256)", to, value));
        require(s && (d.length == 0 || abi.decode(d, (bool))), "TF_FAIL");
    }
    function _safeTransferFrom(address token, address from, address to, uint value) private {
        (bool s, bytes memory d) = token.call(abi.encodeWithSignature("transferFrom(address,address,uint256)", from, to, value));
        require(s && (d.length == 0 || abi.decode(d, (bool))), "TFF_FAIL");
    }
    function _safeApprove(address token, address to, uint value) private {
        (bool s, bytes memory d) = token.call(abi.encodeWithSignature("approve(address,uint256)", to, value));
        require(s && (d.length == 0 || abi.decode(d, (bool))), "AP_FAIL");
    }
    function _addLiquidity(address tokenA, address tokenB, uint amountADesired, uint amountBDesired, uint amountAMin, uint amountBMin) internal returns (uint amountA, uint amountB) {
        if (OPKWFactory(factory).getPair(tokenA, tokenB) == address(0)) { OPKWFactory(factory).createPair(tokenA, tokenB); }
        (uint reserveA, uint reserveB) = getReserves(tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) { (amountA, amountB) = (amountADesired, amountBDesired); }
        else {
            uint amountBOptimal = amountADesired * reserveB / reserveA;
            if (amountBOptimal <= amountBDesired) { require(amountBOptimal >= amountBMin, "INSUFF_B"); (amountA, amountB) = (amountADesired, amountBOptimal); }
            else { uint amountAOptimal = amountBDesired * reserveA / reserveB; require(amountAOptimal <= amountADesired); require(amountAOptimal >= amountAMin, "INSUFF_A"); (amountA, amountB) = (amountAOptimal, amountBDesired); }
        }
    }
    function getReserves(address tokenA, address tokenB) public view returns (uint reserveA, uint reserveB) {
        address pair = OPKWFactory(factory).getPair(tokenA, tokenB);
        (uint112 r0, uint112 r1,) = OPKWPair(pair).getReserves();
        (address t0,) = sortTokens(tokenA, tokenB);
        (reserveA, reserveB) = tokenA == t0 ? (r0, r1) : (r1, r0);
    }
    function sortTokens(address a, address b) public pure returns (address, address) { return a < b ? (a, b) : (b, a); }
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) public pure returns (uint amountOut) {
        require(amountIn > 0 && reserveIn > 0 && reserveOut > 0, "INSUFF");
        uint amountInWithFee = amountIn * 997;
        uint numerator = amountInWithFee * reserveOut;
        uint denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }
    function getAmountsOut(uint amountIn, address[] memory path) public view returns (uint[] memory amounts) {
        require(path.length >= 2, "PATH");
        amounts = new uint[](path.length); amounts[0] = amountIn;
        for (uint i; i < path.length - 1; i++) { (uint rIn, uint rOut) = getReserves(path[i], path[i+1]); amounts[i+1] = getAmountOut(amounts[i], rIn, rOut); }
    }
    function _swap(uint[] memory amounts, address[] memory path, address _to) internal {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i+1]);
            (address token0,) = sortTokens(input, output);
            uint amountOut = amounts[i+1];
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < path.length - 2 ? OPKWFactory(factory).getPair(output, path[i+2]) : _to;
            OPKWPair(OPKWFactory(factory).getPair(input, output)).swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }
    function addLiquidity(address tokenA, address tokenB, uint amountADesired, uint amountBDesired, uint amountAMin, uint amountBMin, address to, uint deadline) external ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = OPKWFactory(factory).getPair(tokenA, tokenB);
        _safeTransferFrom(tokenA, msg.sender, pair, amountA);
        _safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = OPKWPair(pair).mint(to);
    }
    function addLiquidityETH(address token, uint amountTokenDesired, uint amountTokenMin, uint amountETHMin, address to, uint deadline) external payable ensure(deadline) returns (uint amountToken, uint amountETH, uint liquidity) {
        (amountToken, amountETH) = _addLiquidity(token, WETH, amountTokenDesired, msg.value, amountTokenMin, amountETHMin);
        address pair = OPKWFactory(factory).getPair(token, WETH);
        _safeTransferFrom(token, msg.sender, pair, amountToken);
        WOPKW(WETH).deposit{value: amountETH}();
        require(WOPKW(WETH).transfer(pair, amountETH), "W_FAIL");
        liquidity = OPKWPair(pair).mint(to);
        if (msg.value > amountETH) {
            (bool ok, ) = payable(msg.sender).call{value: msg.value - amountETH}("");
            require(ok, "ETH_REFUND_FAIL");
        }
    }
    function removeLiquidity(address tokenA, address tokenB, uint liquidity, uint amountAMin, uint amountBMin, address to, uint deadline) public ensure(deadline) returns (uint amountA, uint amountB) {
        address pair = OPKWFactory(factory).getPair(tokenA, tokenB);
        require(OPKWPair(pair).transferFrom(msg.sender, pair, liquidity), "LP_FAIL");
        (uint balance0, uint balance1) = (IERC20(tokenA).balanceOf(pair), IERC20(tokenB).balanceOf(pair));
        (amountA, amountB) = OPKWPair(pair).burn(to);
        require(amountA >= amountAMin && amountB >= amountBMin, "INSUFF");
    }
    function removeLiquidityETH(address token, uint liquidity, uint amountTokenMin, uint amountETHMin, address to, uint deadline) external ensure(deadline) returns (uint amountToken, uint amountETH) {
        (amountToken, amountETH) = removeLiquidity(token, WETH, liquidity, amountTokenMin, amountETHMin, address(this), deadline);
        _safeTransfer(token, to, amountToken);
        WOPKW(WETH).withdraw(amountETH);
        (bool ok, ) = payable(to).call{value: amountETH}("");
        require(ok, "ETH_FAIL");
    }
    function swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external ensure(deadline) returns (uint[] memory amounts) {
        amounts = getAmountsOut(amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "INSUFF_OUT");
        _safeTransferFrom(path[0], msg.sender, OPKWFactory(factory).getPair(path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
    }
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline) external payable ensure(deadline) returns (uint[] memory amounts) {
        require(path[0] == WETH, "BAD_PATH");
        amounts = getAmountsOut(msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "INSUFF_OUT");
        WOPKW(WETH).deposit{value: amounts[0]}();
        require(WOPKW(WETH).transfer(OPKWFactory(factory).getPair(path[0], path[1]), amounts[0]), "W_FAIL");
        _swap(amounts, path, to);
    }
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external ensure(deadline) returns (uint[] memory amounts) {
        require(path[path.length - 1] == WETH, "BAD_PATH");
        amounts = getAmountsOut(amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "INSUFF_OUT");
        _safeTransferFrom(path[0], msg.sender, OPKWFactory(factory).getPair(path[0], path[1]), amounts[0]);
        _swap(amounts, path, address(this));
        WOPKW(WETH).withdraw(amounts[amounts.length - 1]);
        (bool ok, ) = payable(to).call{value: amounts[amounts.length - 1]}("");
        require(ok, "ETH_FAIL");
    }
}
