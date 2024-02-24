// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;
import { ILendingPool } from "../interfaces/ILendingPool.sol";

interface ILToken {
	function balanceOf(address user) external view returns (uint256);

	function transferUnderlyingTo(
		address asset,
		address target,
		uint256 amount
	) external returns (uint256);

	function mint(address user, uint256 amount) external returns (bool);

	function burn(
		address asset,
		address user,
		address receiverOfUnderlying,
		uint256 amount
	) external;
}

interface IVdToken {
	function mint(address user, uint256 amount) external returns (bool);

	function burn(address user, uint256 amount) external;

	function balanceOf(address user) external view returns (uint256);
}

interface IERC20 {
	function balanceOf(address account) external returns (uint256);

	function transfer(address recipient, uint256 amount) external returns (bool);

	function approve(address spender, uint256 amount) external returns (bool);

	function transferFrom(
		address sender,
		address recipient,
		uint256 amount
	) external returns (bool);

	function approveDelegation(address delegatee, uint256 amount) external;
}

contract LendingPool is ILendingPool {
	address[] public assets;
	mapping(address => ReserveData) public reserves;

	constructor(address _asset, address _ltoken, address _vdToken) {
		_addAsset(_asset, _ltoken, _vdToken);
	}

	function addAsset(
		address _asset,
		address _ltoken,
		address _vdToken
	) external {
		_addAsset(_asset, _ltoken, _vdToken);
	}

	function _addAsset(
		address _asset,
		address _ltoken,
		address _vdToken
	) internal {
		ReserveConfigurationMap memory config = ReserveConfigurationMap(8000);
		config.data = uint256(
			8000 + // ltv: 80%
				(8500 << 16) + // liquidationThreshold: 85%
				(500 << 32) + // liquidationBonus: 5%
				(18 << 48) + // decimals: 18
				(1 << 56) + // isActive: true
				(0 << 57) + // isFrozen: false
				(1 << 58) + // borrowingEnabled: true
				(1 << 59) + // stableBorrowRateEnabled: true
				(0 << 60) + // reserved: none
				(1000 << 64) // reserveFactor: 10%
		);
		assets.push(_asset);
		reserves[_asset] = ReserveData(
			config,
			0,
			0,
			0,
			0,
			0,
			0,
			_ltoken,
			address(0),
			_vdToken,
			address(0),
			0
		);
	}

	/**
	 * @dev Deposits an `amount` of underlying asset into the reserve, receiving in return overlying lTokens.
	 * - E.g. User deposits 100 USDC and gets in return 100 lUSDC
	 * @param asset The address of the underlying asset to deposit
	 * @param amount The amount to be deposited
	 * @param onBehalfOf The address that will receive the lTokens, same as msg.sender if the user
	 *   wants to receive them on his own wallet, or a different address if the benetotalBorrow
	 **/
	function deposit(
		address asset,
		uint256 amount,
		address onBehalfOf,
		uint16 referralCode
	) external {
		IERC20(asset).transferFrom(
			msg.sender,
			reserves[asset].lTokenAddress,
			amount
		);
		ILToken(reserves[asset].lTokenAddress).mint(onBehalfOf, amount);
	}

	/**
	 * @dev Withdraws an `amount` of underlying asset from the reserve, burning the equivalent lTokens owned
	 * E.g. User has 100 lUSDC, calls withdraw() and receives 100 USDC, burning the 100 lUSDC
	 * @param asset The address of the underlying asset to withdraw
	 * @param amount The underlying amount to be withdrawn
	 *   - Send the value type(uint256).max in order to withdraw the whole lToken balance
	 * @param to Address that will receive the underlying, same as msg.sender if the user
	 *   wants to receive it on his own wallet, or a different address if the beneficiary is a
	 *   different wallet
	 * @return The final amount withdrawn
	 **/
	function withdraw(
		address asset,
		uint256 amount,
		address to
	) external returns (uint256) {
		uint256 userBalance = ILToken(reserves[asset].lTokenAddress).balanceOf(
			msg.sender
		);

		uint256 amountToWithdraw = amount;
		if (amount == type(uint256).max) {
			amountToWithdraw = userBalance;
		}
		ILToken(reserves[asset].lTokenAddress).burn(
			asset,
			to,
			to,
			amountToWithdraw
		);
		return amountToWithdraw;
	}

	/**
	 * @dev Allows users to borrow a specific `amount` of the reserve underlying asset, provided that the borrower
	 * already deposited enough collateral, or he was given enough allowance by a credit delegator on the
	 * corresponding debt token (StableDebtToken or VariableDebtToken)
	 * - E.g. User borrows 100 USDC passing as `onBehalfOf` his own address, receiving the 100 USDC in his wallet
	 *   and 100 stable/variable debt tokens, depending on the `interestRateMode`
	 * @param asset The address of the underlying asset to borrow
	 * @param amount The amount to be borrowed
	 * @param interestRateMode The interest rate mode at which the user wants to borrow: 1 for Stable, 2 for Variable
	 * @param referralCode Code used to register the integrator originating the operation, for potential rewards.
	 *   0 if the action is executed directly by the user, without any middle-man
	 * @param onBehalfOf Address of the user who will receive the debt. Should be the address of the borrower itself
	 * calling the function if he wants to borrow against his own collateral, or the address of the credit delegator
	 * if he has been given credit delegation allowance
	 **/
	function borrow(
		address asset,
		uint256 amount,
		uint256 interestRateMode,
		uint16 referralCode,
		address onBehalfOf
	) external {
		ILToken(reserves[asset].lTokenAddress).transferUnderlyingTo(
			asset,
			msg.sender,
			amount
		);
		IVdToken(reserves[asset].variableDebtTokenAddress).mint(onBehalfOf, amount);
	}

	/**
	 * @notice Repays a borrowed `amount` on a specific reserve, burning the equivalent debt tokens owned
	 * - E.g. User repays 100 USDC, burning 100 variable/stable debt tokens of the `onBehalfOf` address
	 * @param asset The address of the borrowed underlying asset previously borrowed
	 * @param amount The amount to repay
	 * - Send the value type(uint256).max in order to repay the whole debt for `asset` on the specific `debtMode`
	 * @param rateMode The interest rate mode at of the debt the user wants to repay: 1 for Stable, 2 for Variable
	 * @param onBehalfOf Address of the user who will get his debt reduced/removed. Should be the address of the
	 * user calling the function if he wants to reduce/remove his own debt, or the address of any other
	 * other borrower whose debt should be removed
	 * @return The final amount repaid
	 **/
	function repay(
		address asset,
		uint256 amount,
		uint256 rateMode,
		address onBehalfOf
	) external returns (uint256) {
		uint256 paybackAmount = IERC20(asset).balanceOf(msg.sender);

		if (amount < paybackAmount) {
			paybackAmount = amount;
		}
		IERC20(asset).transferFrom(
			msg.sender,
			reserves[asset].lTokenAddress,
			paybackAmount
		);
		IVdToken(reserves[asset].variableDebtTokenAddress).burn(
			onBehalfOf,
			paybackAmount
		);
		return paybackAmount;
	}

	/**
	 * @dev Returns the configuration of the reserve
	 * @param asset The address of the underlying asset of the reserve
	 * @return The configuration of the reserve
	 **/
	function getConfiguration(
		address asset
	) external view returns (ReserveConfigurationMap memory) {
		return reserves[asset].configuration;
	}

	/**
	 * @dev Returns the state and configuration of the reserve
	 * @param _asset The address of the underlying asset of the reserve
	 * @return The state of the reserve
	 **/
	function getReserveData(
		address _asset
	) external view returns (ReserveData memory) {
		return reserves[_asset];
	}

	function getUserAccountData(
		address user
	)
		external
		view
		override
		returns (
			uint256 totalCollateralETH,
			uint256 totalDebtETH,
			uint256 availableBorrowsETH,
			uint256 currentLiquidationThreshold,
			uint256 ltv,
			uint256 healthFactor
		)
	{
		uint256 totalColWithLiqThreshold;
		for (uint256 i = 0; i < assets.length; i++) {
			ReserveData memory reserve = reserves[assets[i]];
			uint256 userCollateralBalance = ILToken(reserve.lTokenAddress).balanceOf(
				user
			);

			uint256 assetLiqThreshold = reserve.configuration.data & 0xffff;
			totalCollateralETH += userCollateralBalance;
			totalColWithLiqThreshold += ((userCollateralBalance * assetLiqThreshold));
			uint256 userDebtBalance = IVdToken(reserve.variableDebtTokenAddress)
				.balanceOf(user);
			totalDebtETH += userDebtBalance;
		}
		currentLiquidationThreshold = totalCollateralETH == 0
			? 0
			: totalColWithLiqThreshold / totalCollateralETH;
		healthFactor = totalDebtETH == 0
			? type(uint256).max
			: totalCollateralETH / totalDebtETH;
		return (
			totalCollateralETH,
			totalDebtETH,
			0,
			currentLiquidationThreshold,
			0,
			healthFactor
		);
	}
}
