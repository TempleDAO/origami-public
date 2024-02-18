pragma solidity 0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/external/stakedao/IStakeDao_VeSDT.sol)

interface IStakeDao_VeSDT {
    event Deposit(address indexed provider, uint256 value, uint256 indexed locktime, int128 _type, uint256 ts);

    struct LockedBalance {
        int128 amount;
        uint256 end;
    }
	struct Point {
		int128 bias;
		int128 slope; // - dweight / dt
		uint256 ts;
		uint256 blk; // block
	}
    function create_lock(uint256 _value, uint256 _unlock_time) external;
    function increase_amount(uint256 _value) external;
    function increase_unlock_time(uint256 _unlock_time) external;
    function withdraw() external;
    function balanceOf(address addr, uint256 _t) external view returns (uint256);
    function balanceOf(address addr) external view returns (uint256); // Uses block.timestamp as default
    function totalSupply(uint256 t) external view returns (uint256);
    function totalSupply() external view returns (uint256); // Uses block.timestamp as default
    function checkpoint() external;
    function locked(address addr) external view returns (LockedBalance memory);
    function epoch() external view returns (uint256);
	function point_history(uint256 _epoch) external view returns (Point memory);

	// Functions for determining amount to claim
	function user_point_epoch(address user) external view returns (uint256);
	function user_point_history(address user, uint256 user_epoch) external view returns (Point memory);
}