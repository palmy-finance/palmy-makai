pragma solidity 0.8.10;

interface IPriceOracleGetter {
	/**
	 * @dev returns the asset price in ASTR
	 * @param asset the address of the asset
	 * @return the ASTR price of the asset
	 **/
	function getAssetPrice(address asset) external view returns (uint256);
}
