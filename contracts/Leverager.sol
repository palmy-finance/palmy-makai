// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "./interfaces/IERC20.sol";
import "./interfaces/IWOAS.sol";
import "./interfaces/ILendingPool.sol";
import "./interfaces/IPriceOracleGetter.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract Leverager is Initializable {
	uint16 internal constant LEVERAGE_CODE = 10;
	uint256 internal constant LTV_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000; // prettier-ignore
	uint256 internal constant LT_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000; // prettier-ignore
	uint256 constant DECIMALS_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00FFFFFFFFFFFF; // prettier-ignore
	uint256 constant RESERVE_DECIMALS_START_BIT_POSITION = 48;
	uint256 internal constant MAX_INT = 2 ** 256 - 1;
	uint256 internal constant ETH = 1 ether;
	uint256 internal constant CLOSE_MAX_LOOPS = 40;

	address public lendingPool;
	IWOAS public woas;
	IPriceOracleGetter public priceOracleGetter;

	function initialize(
		address pool,
		address _woas,
		address palmyOracle
	) external initializer {
		lendingPool = pool;
		woas = IWOAS(_woas);
		priceOracleGetter = IPriceOracleGetter(palmyOracle);
	}

	/// @notice Loop the depositing and borrowing
	/// @param asset The address of the target token
	/// @param amount The total deposit amount
	/// @param interestRateMode The interest rate mode at which the user wants to borrow: 1 for Stable, 2 for Variable
	/// @param borrowRatio the percentage of the usage of the borrowed amount
	///                        e.g. 80% -> 8000
	/// @param loopCount The looping count how many times to deposit
	function loop(
		address asset,
		uint256 amount,
		uint256 interestRateMode,
		uint256 borrowRatio,
		uint256 loopCount
	) public {
		_validateLoop(asset, borrowRatio, loopCount);

		require(
			IERC20(asset).transferFrom(msg.sender, address(this), amount),
			"Transfer failed"
		);
		IERC20(asset).approve(lendingPool, MAX_INT);
		_loop(asset, amount, interestRateMode, borrowRatio, loopCount);
	}

	function _validateLoop(
		address asset,
		uint256 borrowRatio,
		uint256 loopCount
	) internal view {
		uint256 _ltv = ltv(asset);
		require(
			borrowRatio > 0 && borrowRatio <= _ltv,
			"Inappropriate borrow rate"
		);
		require(loopCount >= 2 && loopCount <= 40, "Inappropriate loop count");
	}

	/// @notice Loop the depositing and borrowing on OAS
	/// @param interestRateMode The interest rate mode at which the user wants to borrow: 1 for Stable, 2 for Variable
	/// @param borrowRatio the percentage of the usage of the borrowed amount
	///                        e.g. 80% -> 8000
	/// @param loopCount The looping count how many times to deposit
	function loopOAS(
		uint256 interestRateMode,
		uint256 borrowRatio,
		uint256 loopCount
	) external payable {
		_validateLoop(address(woas), borrowRatio, loopCount);

		woas.approve(lendingPool, MAX_INT);
		woas.deposit{ value: msg.value }();
		_loop(address(woas), msg.value, interestRateMode, borrowRatio, loopCount);
	}

	function getConfiguration(address asset) public view returns (uint256 data) {
		data = ILendingPool(lendingPool).getConfiguration(asset).data;
	}

	function getLToken(address asset) public view returns (address) {
		return ILendingPool(lendingPool).getReserveData(asset).lTokenAddress;
	}

	function getVDToken(address asset) public view returns (address) {
		return
			ILendingPool(lendingPool).getReserveData(asset).variableDebtTokenAddress;
	}

	function getAvailableBorrows(
		address account
	)
		external
		view
		returns (
			uint256 totalCollateral, // decimal 8
			uint256 availableBorrows, // decimal 8
			uint256 priceOAS, // decimal 8
			uint256 available,
			uint256 _ltv,
			uint256 hf // decimal 18
		)
	{
		(totalCollateral, , availableBorrows, , _ltv, hf) = ILendingPool(
			lendingPool
		).getUserAccountData(account);
		priceOAS = priceOracleGetter.getAssetPrice(address(woas));
		available = availableBorrows * priceOAS;
	}

	function withdrawable(
		address account,
		address asset
	)
		public
		view
		returns (
			uint256 totalCollateral, // decimal 8
			uint256 totalDebt, // decimal 8
			uint256 currentLiquidationThreshold, //decimal 2
			uint256 afford, // decimal 8
			uint256 withdrawableCollateral,
			uint256 withdrawAmount
		)
	{
		(
			totalCollateral,
			totalDebt,
			,
			currentLiquidationThreshold,
			,

		) = ILendingPool(lendingPool).getUserAccountData(account);

		uint256 decimal = (ILendingPool(lendingPool)
			.getReserveData(asset)
			.configuration
			.data & ~DECIMALS_MASK) >> RESERVE_DECIMALS_START_BIT_POSITION;
		uint256 reserveUnitPrice = priceOracleGetter.getAssetPrice(asset);
		uint256 liqThreshold = lt(asset);
		afford =
			totalCollateral *
			currentLiquidationThreshold -
			totalDebt *
			10 ** (4);
		withdrawableCollateral =
			((10 ** (decimal)) * afford) /
			(reserveUnitPrice * liqThreshold);
		withdrawAmount = withdrawableCollateral;
		GetHealthFactorAfterWithdrawLocalVars
			memory vars = _getHealthFactorLocalVars(account, asset);
		uint256 healthFactor = _getHealthFactor(vars, withdrawAmount);

		// The calculated withdrawAmount does not saticfy healthFactor > 1 due to numerical error
		// The withdrawAmount will be decrease until healthFactor > 1.01
		while (healthFactor <= (101 * ETH) / 100) {
			withdrawAmount = (withdrawAmount * 95) / 100; // decrease withdraw amount
			healthFactor = _getHealthFactor(vars, withdrawAmount);
		}
	}

	struct GetHealthFactorAfterWithdrawLocalVars {
		uint256 totalCollateral;
		uint256 totalDebt;
		uint256 currentLiquidationThreshold;
		uint8 decimals;
		uint256 reserveUnitPrice;
		uint256 liqThreshold;
	}

	function _getHealthFactor(
		GetHealthFactorAfterWithdrawLocalVars memory vars,
		uint256 withdrawAmount
	) internal pure returns (uint256) {
		uint256 amountETH = (withdrawAmount * vars.reserveUnitPrice) /
			(10 ** (vars.decimals));
		(
			uint256 totalCollateralAfter,
			uint256 liquidationThresholdAfter
		) = _calculateAfterWithdraw(
				vars.totalCollateral,
				amountETH,
				vars.currentLiquidationThreshold,
				vars.liqThreshold
			);

		return
			wadDiv(
				percentMul(totalCollateralAfter, liquidationThresholdAfter),
				vars.totalDebt
			);
	}

	function _getHealthFactorLocalVars(
		address account,
		address asset
	) internal view returns (GetHealthFactorAfterWithdrawLocalVars memory) {
		(
			uint256 totalCollateral,
			uint256 totalDebt,
			,
			uint256 currentLiquidationThreshold,
			,

		) = ILendingPool(lendingPool).getUserAccountData(account);

		uint8 decimal = IERC20(asset).decimals();
		uint256 reserveUnitPrice = priceOracleGetter.getAssetPrice(asset);
		uint256 liqThreshold = lt(asset);

		return
			GetHealthFactorAfterWithdrawLocalVars(
				totalCollateral,
				totalDebt,
				currentLiquidationThreshold,
				decimal,
				reserveUnitPrice,
				liqThreshold
			);
	}

	function getHealthFactor(
		address account,
		address asset,
		uint256 withdrawAmount
	) public view returns (uint256) {
		return
			_getHealthFactor(
				_getHealthFactorLocalVars(account, asset),
				withdrawAmount
			);
	}

	function _calculateAfterWithdraw(
		uint256 totalCol,
		uint256 withdrawAmtEth,
		uint256 currentUserLiqThreshold,
		uint256 assetLiqThreshold
	)
		internal
		pure
		returns (uint256 totalColAfterWithdraw, uint256 liqThresholdAfterWithdraw)
	{
		if (totalCol <= withdrawAmtEth) {
			return (0, 0);
		}
		totalColAfterWithdraw = totalCol - withdrawAmtEth;
		bool thresholdCrossed = currentUserLiqThreshold * totalCol <=
			assetLiqThreshold * withdrawAmtEth;
		if (thresholdCrossed) {
			return (totalColAfterWithdraw, 0);
		}
		uint256 numerator = currentUserLiqThreshold *
			totalCol -
			assetLiqThreshold *
			withdrawAmtEth;
		uint256 denominator = totalColAfterWithdraw;

		return (totalColAfterWithdraw, numerator / denominator);
	}

	/**
	 * @dev Divides two wad, rounding half up to the nearest wad
	 * @param a Wad
	 * @param b Wad
	 * @return The result of a/b, in wad
	 **/
	function wadDiv(uint256 a, uint256 b) internal pure returns (uint256) {
		uint256 WAD = 1e18;
		require(b != 0);
		uint256 halfB = b / 2;

		require(a <= (type(uint256).max - halfB) / WAD);

		return (a * WAD + halfB) / b;
	}

	/**
	 * @dev Executes a percentage multiplication
	 * @param value The value of which the percentage needs to be calculated
	 * @param percentage The percentage of the value to be calculated
	 * @return The percentage of value
	 **/
	function percentMul(
		uint256 value,
		uint256 percentage
	) internal pure returns (uint256) {
		uint256 PERCENTAGE_FACTOR = 1e4; //percentage plus two decimals
		uint256 HALF_PERCENT = PERCENTAGE_FACTOR / 2;
		if (value == 0 || percentage == 0) {
			return 0;
		}

		require(value <= (type(uint256).max - HALF_PERCENT) / percentage);

		return (value * percentage + HALF_PERCENT) / PERCENTAGE_FACTOR;
	}

	/// @notice Loop the repaying and withdrawing
	/// @param asset The address of the target token
	function close(address asset) external {
		address vdToken = getVDToken(asset);
		address lToken = getLToken(asset);

		IERC20(lToken).approve(lendingPool, MAX_INT);
		IERC20(asset).approve(lendingPool, MAX_INT);
		uint256 withdrawAmount = withdrawableAmount(msg.sender, asset);
		uint256 repayAmount = IERC20(vdToken).balanceOf(msg.sender);
		uint256 loopRemains = CLOSE_MAX_LOOPS;
		while (loopRemains > 0 && withdrawAmount > 0) {
			if (withdrawAmount > repayAmount) {
				withdrawAmount = repayAmount;
				require(
					IERC20(lToken).transferFrom(
						msg.sender,
						address(this),
						withdrawAmount
					),
					"Transfer failed"
				);
				ILendingPool(lendingPool).withdraw(
					asset,
					withdrawAmount,
					address(this)
				);
				ILendingPool(lendingPool).repay(asset, withdrawAmount, 2, msg.sender);
				break;
			} else {
				require(
					IERC20(lToken).transferFrom(
						msg.sender,
						address(this),
						withdrawAmount
					),
					"Transfer failed"
				);
				ILendingPool(lendingPool).withdraw(
					asset,
					withdrawAmount,
					address(this)
				);
				ILendingPool(lendingPool).repay(asset, withdrawAmount, 2, msg.sender);
				withdrawAmount = withdrawableAmount(msg.sender, asset);
				repayAmount = IERC20(vdToken).balanceOf(msg.sender);
				loopRemains--;
			}
		}
	}

	function withdrawableAmount(
		address user,
		address asset
	) internal view returns (uint256) {
		(, , , , , uint256 withdrawAmount) = withdrawable(user, asset);
		return withdrawAmount;
	}

	/// @notice Get Loan to value of the asset.
	/// @param asset address of the target token
	/// @return ltv percentage: e.g. 80% -> 8000
	function ltv(address asset) public view returns (uint256) {
		uint256 data = getConfiguration(asset);
		return data & ~LTV_MASK;
	}

	/// @notice Get Loan to value of the asset.
	/// @param asset address of the target token
	/// @return lt percentage: e.g. 80% -> 8000
	function lt(address asset) public view returns (uint256) {
		uint256 data = getConfiguration(asset);
		uint256 liqThreshold = data & ~LT_MASK;
		liqThreshold = liqThreshold / (0xFFFF);
		return liqThreshold;
	}

	function _loop(
		address asset,
		uint256 amount,
		uint256 interestRateMode,
		uint256 borrowRatio,
		uint256 loopCount
	) internal {
		uint256 _nextDepositAmount = amount;
		for (uint256 i = 0; i < loopCount - 1; i++) {
			ILendingPool(lendingPool).deposit(
				asset,
				_nextDepositAmount,
				msg.sender,
				LEVERAGE_CODE
			);
			_nextDepositAmount = (_nextDepositAmount * borrowRatio) / 10000;
			if (_nextDepositAmount == 0) {
				break;
			}
			ILendingPool(lendingPool).borrow(
				asset,
				_nextDepositAmount,
				interestRateMode,
				LEVERAGE_CODE,
				msg.sender
			);
		}
		if (_nextDepositAmount != 0) {
			ILendingPool(lendingPool).deposit(
				asset,
				_nextDepositAmount,
				msg.sender,
				0
			);
		}
	}
}
