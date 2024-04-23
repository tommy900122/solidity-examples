// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20SnapshotUpgradeable.sol";
import "./BaseOFTV2.sol";

/// @title OFT V1.2 Contract
/// @notice This contract is version 1.2 of the OFT Standard, enabling cross-chain token transfers between EVM and non-EVM contracts.
/// @dev This contract is only compatible with Endpoint V1.
contract OFTV2 is BaseOFTV2, ERC20SnapshotUpgradeable {
    uint internal ld2sdRate;

    function __OFTV2_init(
        string memory _name,
        string memory _symbol,
        uint8 _sharedDecimals,
        address _lzEndpoint
    ) internal onlyInitializing {
        __ERC20_init(_name, _symbol);
        __BaseOFTV2_init(_sharedDecimals, _lzEndpoint);
        uint8 decimals = decimals();
        require(_sharedDecimals <= decimals, "OFT: sharedDecimals must be <= decimals");
        ld2sdRate = 10**(decimals - _sharedDecimals);
    }

    /************************************************************************
     * public functions
     ************************************************************************/
    function circulatingSupply() public view virtual override returns (uint) {
        return totalSupply();
    }

    function token() public view virtual override returns (address) {
        return address(this);
    }

    /************************************************************************
     * internal functions
     ************************************************************************/
    function _debitFrom(
        address _from,
        uint16,
        bytes32,
        uint _amount
    ) internal virtual override returns (uint) {
        address spender = _msgSender();
        if (_from != spender) _spendAllowance(_from, spender, _amount);
        _burn(_from, _amount);
        return _amount;
    }

    function _creditTo(
        uint16,
        address _toAddress,
        uint _amount
    ) internal virtual override returns (uint) {
        _mint(_toAddress, _amount);
        return _amount;
    }

    function _transferFrom(
        address _from,
        address _to,
        uint _amount
    ) internal virtual override returns (uint) {
        address spender = _msgSender();
        // if transfer from this contract, no need to check allowance
        if (_from != address(this) && _from != spender) _spendAllowance(_from, spender, _amount);
        _transfer(_from, _to, _amount);
        return _amount;
    }

    function _ld2sdRate() internal view virtual override returns (uint) {
        return ld2sdRate;
    }
}
