pragma solidity 0.8.10;

import "../interfaces/IPriceOracleGetter.sol";
contract PriceOracle is IPriceOracleGetter {
	function getAssetPrice(
		address asset
	) external view override returns (uint256) {
        return 1e18;
    }
}