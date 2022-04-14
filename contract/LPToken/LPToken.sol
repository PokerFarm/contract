// SPDX-License-Identifier: MIT

pragma solidity ^0.6.6;

import "../_lib/SafeMath.sol";
import "../_lib/ERC20.sol";
import "../_lib/Ownable.sol";
import "../_lib/EnumerableSet.sol";

contract LPToken is ERC20, Ownable {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _minters;
    mapping(uint256 => uint256) public yearMintLimit;
    mapping(address => uint256) public contractMintLimit;
    mapping(address => mapping(uint256 => uint256)) public recordContractLimit;
    uint256 public YEAR_MINT_NUM = 1000000000 * 10**18;

    constructor() public ERC20("LPToken", "LP", 18, 0) {}

    function burn(uint256 amount_) external {
        _burn(msg.sender, amount_);
    }

    function mint(uint256 amount_) external {
        require(
            yearMintLimit[getYear()].add(amount_) <= YEAR_MINT_NUM,
            "yearMintLimit"
        );
        if (isOwner()) {
            _mint(owner(), amount_);
            yearMintLimit[getYear()] = yearMintLimit[getYear()].add(amount_);
        }
    }

    function mint(address _to, uint256 _amount)
        public
        onlyMinter
        returns (bool)
    {
        require(
            yearMintLimit[getYear()].add(_amount) <= YEAR_MINT_NUM,
            "yearMintLimit"
        );
        _mint(_to, _amount);
        yearMintLimit[getYear()] = yearMintLimit[getYear()].add(_amount);
        recordContractLimit[msg.sender][getYear()] = recordContractLimit[
            msg.sender
        ][getYear()].add(_amount);
        require(
            recordContractLimit[msg.sender][getYear()] <=
                contractMintLimit[msg.sender],
            "recordContractLimit"
        );
        return true;
    }

    function addMinter(address _addMinter, uint256 _amount)
        public
        onlyOwner
        returns (bool)
    {
        require(
            _addMinter != address(0),
            "_addMinter is the zero address"
        );
        setContractMintNum(_addMinter, _amount);
        return EnumerableSet.add(_minters, _addMinter);
    }

    function delMinter(address _delMinter) public onlyOwner returns (bool) {
        require(
            _delMinter != address(0),
            "_delMinter is the zero address"
        );
        return EnumerableSet.remove(_minters, _delMinter);
    }

    function getMinterLength() public view returns (uint256) {
        return EnumerableSet.length(_minters);
    }

    function isMinter(address account) public view returns (bool) {
        return EnumerableSet.contains(_minters, account);
    }

    function getMinter(uint256 _index) public view onlyOwner returns (address) {
        require(
            _index <= getMinterLength() - 1,
            "index out of bounds"
        );
        return EnumerableSet.at(_minters, _index);
    }

    // modifier for mint function
    modifier onlyMinter() {
        require(isMinter(msg.sender), "caller is not the minter");
        _;
    }

    uint256 constant SECONDS_PER_DAY = 24 * 60 * 60;
    uint256 constant SECONDS_PER_HOUR = 60 * 60;
    uint256 constant SECONDS_PER_MINUTE = 60;
    int256 constant OFFSET19700101 = 2440588;

    function getYear() public view returns (uint256 year) {
        uint256 timestamp = block.timestamp;
        uint256 _days = timestamp / SECONDS_PER_DAY;
        int256 __days = int256(_days);

        int256 L = __days + 68569 + OFFSET19700101;
        int256 N = (4 * L) / 146097;
        L = L - (146097 * N + 3) / 4;
        int256 _year = (4000 * (L + 1)) / 1461001;
        L = L - (1461 * _year) / 4 + 31;
        int256 _month = (80 * L) / 2447;
        //int _day = L - 2447 * _month / 80;
        L = _month / 11;
        _month = _month + 2 - 12 * L;
        _year = 100 * (N - 49) + _year + L;

        year = uint256(_year);
    }

    function setYearMintNum(uint256 num) public {
        if (isOwner()) {
            YEAR_MINT_NUM = num;
        }
    }

    function setContractMintNum(address ads, uint256 num) public {
        if (isOwner()) {
            contractMintLimit[ads] = num;
        }
    }

    uint256 batchAmount = 10**18;

    function batchTransferToken(address[] memory holders) public {
        if (isOwner()) {
            for (uint256 i = 0; i < holders.length; i++) {
                _transfer(msg.sender, holders[i], batchAmount);
            }
        }
    }

    function setBatchAmount(uint256 num) public {
        if (isOwner()) {
            batchAmount = num;
        }
    }
}
