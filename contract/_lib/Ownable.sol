// SPDX-License-Identifier: MIT

pragma solidity ^0.6.6;

import "./Context.sol";

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() internal {
        _owner = _msgSender();
        emit OwnershipTransferred(address(0), _owner);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(_msgSender() == _owner, "not owner");
        _;
    }
    
    function isOwner() public view returns (bool){
        bool flag = _msgSender() == _owner;
        require(flag==true,"not owner");
        return flag;
    }

}
