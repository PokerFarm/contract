// SPDX-License-Identifier: MIT
pragma solidity ^0.6.6;

import "../_lib/SafeMath.sol";

interface IPokerToken{
    function totalSupply() external view  returns(uint256);
    function balanceOf(address _owner) external view  returns (uint256);
    function transfer(address _to, uint256 _amount) external  returns (bool);
    function transferFrom(address _from, address _to, uint256 _amount) external  returns (bool);
    function mint(address _to, uint256 _amount) external;
}

contract Active{

    using SafeMath for uint256;

    mapping(address => uint256) public claims;
    address public owner;
    IPokerToken token;

    constructor(IPokerToken _token) public {
        owner = msg.sender;
        token = _token;
    }

    event AdminWrite(uint256 num);
    event Claim(uint256 num);
    event ClaimAll(uint256 num);

    function write(address[] memory _ads,uint256[] memory _num) public {
        require(_ads.length == _num.length,"length err");
        require(owner == msg.sender,"owner err");
        for(uint256 i=0;i<_ads.length;i++){
            claims[_ads[i]] = claims[_ads[i]].add(_num[i]);
        }
        emit AdminWrite(_ads.length);
    }

    function claim(uint256 num) public {
        uint256 myClaim = claims[msg.sender];
        require( myClaim >= num, "num err");
        myClaim = myClaim.sub(num);

        claims[msg.sender] = myClaim;
        token.mint(msg.sender,num);
        
        emit Claim(num);
    }

    function claimAll() public{
        claim(claims[msg.sender]);
        emit ClaimAll(claims[msg.sender]);
    }
}