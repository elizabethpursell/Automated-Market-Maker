// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.4.16 <0.9.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Exchange {

    // State Variables
    uint public contractEthBalance;
    uint public contractERC20TokenBalance;
    uint public totalLiquidityPositions;
    mapping(address=>uint) private mapLiquidityPositions;
    uint public k;
    address public erc20TokenAddress;

    // Constructor
    constructor(address _erc20TokenAddress) {
        erc20TokenAddress = _erc20TokenAddress;
        totalLiquidityPositions = 0;
        k = 0;
    }

    // Events
    event LiquidityProvided(uint amountERC20TokenDeposited, uint amountEthDeposited, uint liquidityPositionsIssued);
    event LiquidityWithdrew(uint amountERC20TokenWithdrew, uint amountEthWithdrew, uint liquidityPositionsBurned);
    event SwapForEth(uint amountERC20TokenDeposited, uint amountEthWithdrew);
    event SwapForERC20Token(uint amountERC20TokenWithdrew, uint amountEthDeposited);

    receive() external payable {
        contractEthBalance += msg.value;
    }

    // Functions
    function provideLiquidity(uint _amountERC20Token) public payable returns (uint)
    {
        require(_amountERC20Token > 0, "You must deposit ERC-20 tokens.");

        uint callerERC20Balance = IERC20(erc20TokenAddress).balanceOf(msg.sender);

        require(callerERC20Balance >= _amountERC20Token, "Caller does not have enough ERC20 tokens");

        uint liquidityPositions;

        if (totalLiquidityPositions == 0) {
            liquidityPositions = 100;
        } else {
            liquidityPositions = (totalLiquidityPositions * _amountERC20Token) / contractERC20TokenBalance;
        }

        require(msg.value > 0, "Caller does not have enough ether");

        payable(address(this)).transfer(msg.value);
        require(IERC20(erc20TokenAddress).transferFrom(msg.sender, address(this), _amountERC20Token), "ERC20 transfer failed");

        contractEthBalance += msg.value;
        contractERC20TokenBalance += _amountERC20Token;
        k = contractEthBalance * contractERC20TokenBalance;

        totalLiquidityPositions += liquidityPositions;
        mapLiquidityPositions[msg.sender] += liquidityPositions;

        emit LiquidityProvided(_amountERC20Token, msg.value, liquidityPositions);
        return liquidityPositions;
    }

    function estimateEthToProvide(uint _amountERC20Token) public view returns (uint)
    {
        uint256 amountEth = contractEthBalance * _amountERC20Token / contractERC20TokenBalance;
        return amountEth;
    }

    function estimateERC20TokenToProvide(uint _amountEth) public view returns (uint)
    {
        uint256 amountERC20 = contractERC20TokenBalance * _amountEth / contractEthBalance;
        return amountERC20;
    }

    function getMyLiquidityPositions() public view returns (uint) 
    {
        return mapLiquidityPositions[msg.sender];
    }

    function withdrawLiquidity(uint256 _liquidityPositionsToBurn) public returns (uint, uint) 
    {
        require(_liquidityPositionsToBurn > 0, "The number of liquidity positions to burn must be greater than 0");
        require(_liquidityPositionsToBurn <= getMyLiquidityPositions(), "Caller can't give up more liquidity positions than they own");
        require(_liquidityPositionsToBurn < totalLiquidityPositions, "Caller can't give up all liquidity positions in the pool");

        uint amountEthToSend = _liquidityPositionsToBurn * contractEthBalance / totalLiquidityPositions;
        uint amountERC20ToSend = _liquidityPositionsToBurn * contractERC20TokenBalance / totalLiquidityPositions;

        require(amountEthToSend <= contractEthBalance, "Not enough Ether in the contract");
        require(amountERC20ToSend <= contractERC20TokenBalance, "Not enough ERC20 tokens in the contract");

        // TODO: Is this how you decrement the user's liquidity?
        mapLiquidityPositions[msg.sender] -= _liquidityPositionsToBurn;
        totalLiquidityPositions -= _liquidityPositionsToBurn;

        contractEthBalance -= amountEthToSend;
        contractERC20TokenBalance -= amountERC20ToSend;
        k = contractEthBalance * contractERC20TokenBalance;

        payable(msg.sender).transfer(amountEthToSend);
        require(IERC20(erc20TokenAddress).transfer(msg.sender, amountERC20ToSend), "ERC20 transfer failed");

        emit LiquidityWithdrew(amountERC20ToSend, amountEthToSend, _liquidityPositionsToBurn);
        return (amountERC20ToSend, amountEthToSend);
    }

    function swapForEth(uint256 _amountERC20Token) public returns (uint) 
    {
        require(_amountERC20Token > 0, "The amount of ERC20 tokens to swap must be greater than 0");
        require(_amountERC20Token <= IERC20(erc20TokenAddress).balanceOf(msg.sender), "Caller doesn't have enough ERC20 tokens");

        uint ethToSend = contractEthBalance - (k / (contractERC20TokenBalance + _amountERC20Token));

        require(contractEthBalance >= ethToSend, "Not enough ether in the contract");

        contractEthBalance -= ethToSend;
        contractERC20TokenBalance += _amountERC20Token;
        k = contractEthBalance * contractERC20TokenBalance;

        require(IERC20(erc20TokenAddress).transferFrom(msg.sender, address(this), _amountERC20Token), "ERC20 transfer failed");
        payable(msg.sender).transfer(ethToSend);

        emit SwapForEth(_amountERC20Token, ethToSend);
        return ethToSend;
    }

    function estimateSwapForEth(uint _amountERC20Token) public view returns (uint)
    {
        uint contractERC20TokenBalanceAfterSwap = contractERC20TokenBalance + _amountERC20Token;
        uint contractEthBalanceAfterSwap = k / contractERC20TokenBalanceAfterSwap;
        uint ethToSend = contractEthBalance - contractEthBalanceAfterSwap;
        return ethToSend;
    }

    function swapForERC20Token(uint _amountEth) public returns (uint){
        require(_amountEth > 0, "The amount of Eth tokens must be greater than 0");
        require(_amountEth <= address(this).balance, "Caller doesn't have enough Eth");

        uint ERC20TokenToSend = contractERC20TokenBalance - (k /(contractEthBalance + _amountEth));
        require(contractERC20TokenBalance >= ERC20TokenToSend, "Not enough ERC20 tokens in the contract");

        contractEthBalance += _amountEth;
        contractERC20TokenBalance -= ERC20TokenToSend;
        k = contractEthBalance * contractERC20TokenBalance;

        payable(address(this)).transfer(_amountEth);
        require(IERC20(erc20TokenAddress).transfer(msg.sender, ERC20TokenToSend));

        emit SwapForERC20Token(ERC20TokenToSend, _amountEth);
        return ERC20TokenToSend;
    }

    function estimateSwapForERC20Token(uint _amountEth) public view returns (uint)
    {
        uint contractEthBalanceAfterSwap = contractEthBalance + _amountEth;
        uint contractERC20TokenBalanceAfterSwap = k / contractEthBalanceAfterSwap;
        uint ERC20TokenToSend = contractERC20TokenBalance - contractERC20TokenBalanceAfterSwap;
        return ERC20TokenToSend;
    }
}
