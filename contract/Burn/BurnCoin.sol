// SPDX-License-Identifier: MIT
pragma solidity ^0.6.6;

interface IPokerToken {
    function totalSupply() external view returns (uint256);

    function balanceOf(address _owner) external view returns (uint256);

    function transfer(address _to, uint256 _amount) external returns (bool);

    function transferFrom(
        address _from,
        address _to,
        uint256 _amount
    ) external returns (bool);

    function mint(address _to, uint256 _amount) external;

    function burn(uint256 _amount) external;
}

contract BurnCoin {
    IPokerToken poker;

    constructor(IPokerToken _poker) public {
        poker = _poker;
    }

    event Burn(address from, uint256 amount);
    event ExchangeBurn(address from, uint256 amount);

    function burn(uint256 _amount) public {
        poker.burn(_amount);
        emit Burn(msg.sender, _amount);
    }

    function exchangeBurn(uint256 _amount) public {
        poker.transferFrom(msg.sender, address(this), _amount);
        poker.burn(_amount);
        emit ExchangeBurn(msg.sender, _amount);
    }
}
