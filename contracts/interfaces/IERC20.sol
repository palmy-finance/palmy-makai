pragma solidity 0.8.10;

interface IERC20 {
	function decimals() external view returns (uint8);

	function balanceOf(address user) external returns (uint256);

	function approve(address spender, uint256 amount) external returns (bool);

	function transfer(address recipient, uint256 amount) external returns (bool);

	function transferFrom(
		address sender,
		address recipient,
		uint256 amount
	) external returns (bool);

	function approveDelegation(address delegatee, uint256 amount) external;
}
