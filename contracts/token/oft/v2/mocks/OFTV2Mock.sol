// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../OFTV2.sol";

// @dev mock OFTV2 demonstrating how to inherit OFTV2
contract OFTV2Mock is OFTV2 {
    mapping(address => bool) public admins;
    mapping(address => bool) public blacklists;

    event SetAdmin(address indexed user, bool indexed auth);
    event SetBlackList(address indexed user, bool indexed auth);

    modifier onlyAdmin() {
        require(owner() == msg.sender || admins[msg.sender], "caller is not admin");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(address _layerZeroEndpoint, uint8 _sharedDecimals) public initializer {
        __OFTV2_init("ExampleOFT", "OFT", _sharedDecimals, _layerZeroEndpoint);
        _mint(_msgSender(), 10_000_000_000 * 10**decimals());
    }

    function setAdmin(address _user, bool _auth) external onlyOwner {
        require(_user != address(0), "invalid user");
        admins[_user] = _auth;
        emit SetAdmin(_user, _auth);
    }

    /// @notice Set the account to the blacklist
    function setBlackList(address _user, bool _auth) public onlyAdmin {
        blacklists[_user] = _auth;
        emit SetBlackList(_user, _auth);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint amount
    ) internal virtual override {
        require(!blacklists[msg.sender], "Sender blacklisted");
        require(!blacklists[from], "From address blacklisted");
        super._beforeTokenTransfer(from, to, amount);
    }
}
