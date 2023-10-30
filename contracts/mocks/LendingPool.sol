// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;
import "hardhat/console.sol";

interface ILToken {
  function balanceOf(address user) external returns (uint256);

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

contract LendingPool {
  address public ltoken;
  address public asset;
  mapping(address => uint256) public totalBorrow;
  mapping(address => uint256) public totalDeposit;

  struct ReserveConfigurationMap {
    //bit 0-15: LTV
    //bit 16-31: Liq. threshold
    //bit 32-47: Liq. bonus
    //bit 48-55: Decimals
    //bit 56: Reserve is active
    //bit 57: reserve is frozen
    //bit 58: borrowing is enabled
    //bit 59: stable rate borrowing enabled
    //bit 60-63: reserved
    //bit 64-79: reserve factor
    uint256 data;
  }
  // refer to the whitepaper, section 1.1 basic concepts for a formal description of these properties.
  struct ReserveData {
    //stores the reserve configuration
    ReserveConfigurationMap configuration;
    //the liquidity index. Expressed in ray
    uint128 liquidityIndex;
    //variable borrow index. Expressed in ray
    uint128 variableBorrowIndex;
    //the current supply rate. Expressed in ray
    uint128 currentLiquidityRate;
    //the current variable borrow rate. Expressed in ray
    uint128 currentVariableBorrowRate;
    //the current stable borrow rate. Expressed in ray
    uint128 currentStableBorrowRate;
    uint40 lastUpdateTimestamp;
    //tokens addresses
    address lTokenAddress;
    address stableDebtTokenAddress;
    address variableDebtTokenAddress;
    //address of the interest rate strategy
    address interestRateStrategyAddress;
    //the id of the reserve. Represents the position in the list of the active reserves
    uint8 id;
  }

  constructor(address _asset, address _ltoken) {
    asset = _asset;
    ltoken = _ltoken;
  }

  /**
   * @dev Deposits an `amount` of underlying asset into the reserve, receiving in return overlying lTokens.
   * - E.g. User deposits 100 USDC and gets in return 100 lUSDC
   * @param asset The address of the underlying asset to deposit
   * @param amount The amount to be deposited
   * @param onBehalfOf The address that will receive the lTokens, same as msg.sender if the user
   *   wants to receive them on his own wallet, or a different address if the beneficiary of lTokens
   *   is a different wallet
   * @param referralCode Code used to register the integrator originating the operation, for potential rewards.
   *   0 if the action is executed directly by the user, without any middle-man
   **/
  function deposit(
    address asset,
    uint256 amount,
    address onBehalfOf,
    uint16 referralCode
  ) external {
    IERC20(asset).transferFrom(msg.sender, ltoken, amount);
    //ILToken(ltoken).mint(onBehalfOf, amount);
    totalDeposit[asset] += amount;
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
    uint256 userBalance = totalDeposit[asset];

    uint256 amountToWithdraw = amount;
    if (amount == type(uint256).max) {
      amountToWithdraw = userBalance;
    }
    ILToken(ltoken).burn(asset, to, to, amountToWithdraw);
    totalDeposit[asset] -= amountToWithdraw;
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
    ILToken(ltoken).transferUnderlyingTo(asset, msg.sender, amount);
    totalBorrow[asset] += amount;
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
    uint256 paybackAmount = totalBorrow[asset];

    if (amount < paybackAmount) {
      paybackAmount = amount;
    }
    IERC20(asset).transferFrom(msg.sender, ltoken, paybackAmount);
    totalBorrow[asset] -= paybackAmount;
    return paybackAmount;
  }

  /**
   * @dev Returns the configuration of the reserve
   * @param asset The address of the underlying asset of the reserve
   * @return The configuration of the reserve
   **/
  function getConfiguration(address asset)
    external
    pure
    returns (ReserveConfigurationMap memory)
  {
    return ReserveConfigurationMap(8000);
  }

  /**
   * @dev Returns the state and configuration of the reserve
   * @param asset The address of the underlying asset of the reserve
   * @return The state of the reserve
   **/
  function getReserveData(address asset)
    external
    view
    returns (ReserveData memory)
  {}
}
