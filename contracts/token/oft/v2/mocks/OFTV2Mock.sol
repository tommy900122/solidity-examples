// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../OFTV2.sol";
import "../interfaces/IERC7641.sol";

// @dev mock OFTV2 demonstrating how to inherit OFTV2
contract OFTV2Mock is OFTV2, IERC7641 {
    /**
     * @dev snapshot number reserved for claimable
     */
    uint public constant SNAPSHOT_CLAIMABLE_NUMBER = 2;

    /**
     * @dev last snapshotted block
     */
    uint public lastSnapshotBlock;

    /**
     * @dev percentage claimable
     */
    uint public percentClaimable;

    /**
     * @dev snapshot interval
     */
    uint public snapshotInterval;

    /**
     * @dev mapping from snapshot id to the amount of ETH claimable at the snapshot.
     */
    mapping(uint => uint) private _claimableAtSnapshot;

    /**
     * @dev mapping from snapshot id to amount of ETH claimed at the snapshot.
     */
    mapping(uint => uint) private _claimedAtSnapshot;

    /**
     * @dev mapping from snapshot id to a boolean indicating whether the address has claimed the revenue.
     */
    mapping(uint => mapping(address => bool)) private _hasClaimedAtSnapshot;

    /**
     * @dev burn pool
     */
    uint private _redeemPool;

    /**
     * @dev burned from new revenue
     */
    uint private _redeemed;

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

    function initialize(
        address _layerZeroEndpoint,
        uint8 _sharedDecimals,
        uint _percentClaimable,
        uint _snapshotInterval
    ) public initializer {
        __OFTV2_init("ExampleOFT", "OFT", _sharedDecimals, _layerZeroEndpoint);
        percentClaimable = _percentClaimable;
        snapshotInterval = _snapshotInterval;
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

    /**
     * @dev A function to calculate the amount of ETH claimable by a token holder at certain snapshot.
     * @param account The address of the token holder
     * @param snapshotId The snapshot id
     * @return claimable The amount of revenue ETH claimable
     */
    function claimableRevenue(address account, uint snapshotId) public view returns (uint) {
        require(_hasClaimedAtSnapshot[snapshotId][account] == false, "already claimed");
        uint currentSnapshotId = _getCurrentSnapshotId();
        require(currentSnapshotId - snapshotId < SNAPSHOT_CLAIMABLE_NUMBER, "snapshot unclaimable");
        uint balance = balanceOfAt(account, snapshotId);
        uint totalSupply = totalSupplyAt(snapshotId);
        uint ethClaimable = _claimableAtSnapshot[snapshotId];
        return (balance * ethClaimable) / totalSupply;
    }

    /**
     * @dev A function for token holder to claim revenue token based on the token balance at certain snapshot.
     * @param snapshotId The snapshot id
     */
    function claim(uint snapshotId) public {
        uint claimableETH = claimableRevenue(msg.sender, snapshotId);
        require(claimableETH > 0, "no claimable ETH");

        _hasClaimedAtSnapshot[snapshotId][msg.sender] = true;
        _claimedAtSnapshot[snapshotId] += claimableETH;
        (bool success, ) = msg.sender.call{value: claimableETH}("");
        require(success, "claim failed");
    }

    /**
     * @dev A function to claim by a list of snapshot ids.
     * @param snapshotIds The list of snapshot ids
     */
    function claimBatch(uint[] memory snapshotIds) external {
        uint len = snapshotIds.length;
        for (uint i; i < len; ++i) {
            claim(snapshotIds[i]);
        }
    }

    /**
     * @dev A function to calculate claim pool from most recent two snapshots
     * @param currentSnapshotId The current snapshot id
     * @notice modify when SNAPSHOT_CLAIMABLE_NUMBER changes
     */
    function _claimPool(uint currentSnapshotId) private view returns (uint claimable) {
        claimable = _claimableAtSnapshot[currentSnapshotId] - _claimedAtSnapshot[currentSnapshotId];
        if (currentSnapshotId >= 2) claimable += _claimableAtSnapshot[currentSnapshotId - 1] - _claimedAtSnapshot[currentSnapshotId - 1];
        return claimable;
    }

    /**
     * @dev A snapshot function that also records the deposited ETH amount at the time of the snapshot.
     * @return snapshotId The snapshot id
     * @notice 648000 blocks is approximately 3 months
     */
    function snapshot() external returns (uint) {
        require(block.number - lastSnapshotBlock > snapshotInterval, "snapshot interval is too short");
        uint snapshotId = _snapshot();
        lastSnapshotBlock = block.number;

        uint newRevenue = address(this).balance + _redeemed - _redeemPool - _claimPool(snapshotId - 1);

        uint claimableETH = (newRevenue * percentClaimable) / 100;
        _claimableAtSnapshot[snapshotId] = snapshotId < SNAPSHOT_CLAIMABLE_NUMBER
            ? claimableETH
            : claimableETH +
                _claimableAtSnapshot[snapshotId - SNAPSHOT_CLAIMABLE_NUMBER] -
                _claimedAtSnapshot[snapshotId - SNAPSHOT_CLAIMABLE_NUMBER];
        _redeemPool += newRevenue - claimableETH - _redeemed;
        _redeemed = 0;

        return snapshotId;
    }

    /**
     * @dev An internal function to calculate the amount of ETH redeemable in both the newRevenue and burnPool by a token holder upon burn
     * @param amount The amount of token to burn
     * @return redeemableFromNewRevenue The amount of revenue ETH redeemable from the un-snapshoted revenue
     * @return redeemableFromPool The amount of revenue ETH redeemable from the snapshoted redeem pool
     */
    function _redeemableOnBurn(uint amount) private view returns (uint, uint) {
        uint totalSupply = totalSupply();
        uint currentSnapshotId = _getCurrentSnapshotId();
        uint newRevenue = address(this).balance + _redeemed - _redeemPool - _claimPool(currentSnapshotId);
        uint redeemableFromNewRevenue = (amount * ((newRevenue * (100 - percentClaimable)) / 100 - _redeemed)) / totalSupply;
        uint redeemableFromPool = (amount * _redeemPool) / totalSupply;
        return (redeemableFromNewRevenue, redeemableFromPool);
    }

    /**
     * @dev A function to calculate the amount of ETH redeemable by a token holder upon burn
     * @param amount The amount of token to burn
     * @return redeemable The amount of revenue ETH redeemable
     */
    function redeemableOnBurn(uint amount) external view returns (uint) {
        (uint redeemableFromNewRevenue, uint redeemableFromPool) = _redeemableOnBurn(amount);
        return redeemableFromNewRevenue + redeemableFromPool;
    }

    /**
     * @dev A function to burn tokens and redeem the corresponding amount of revenue token
     * @param amount The amount of token to burn
     */
    function burn(uint amount) external {
        (uint redeemableFromNewRevenue, uint redeemableFromPool) = _redeemableOnBurn(amount);
        _redeemPool -= redeemableFromPool;
        _redeemed += redeemableFromNewRevenue;
        _burn(msg.sender, amount);
        (bool success, ) = msg.sender.call{value: redeemableFromNewRevenue + redeemableFromPool}("");
        require(success, "burn failed");
    }

    receive() external payable {}

    /**
     * @dev override _beforeTokenTransfer to update the snapshot
     */
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
