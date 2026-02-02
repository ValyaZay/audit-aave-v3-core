// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import {GPv2SafeERC20} from '../../../dependencies/gnosis/contracts/GPv2SafeERC20.sol';
import {SafeCast} from '../../../dependencies/openzeppelin/contracts/SafeCast.sol';
import {IERC20} from '../../../dependencies/openzeppelin/contracts/IERC20.sol';
import {IStableDebtToken} from '../../../interfaces/IStableDebtToken.sol';
import {IVariableDebtToken} from '../../../interfaces/IVariableDebtToken.sol';
import {IAToken} from '../../../interfaces/IAToken.sol';
import {UserConfiguration} from '../configuration/UserConfiguration.sol';
import {ReserveConfiguration} from '../configuration/ReserveConfiguration.sol';
import {Helpers} from '../helpers/Helpers.sol';
import {DataTypes} from '../types/DataTypes.sol';
import {ValidationLogic} from './ValidationLogic.sol';
import {ReserveLogic} from './ReserveLogic.sol';
import {IsolationModeLogic} from './IsolationModeLogic.sol';

/**
 * @title BorrowLogic library
 * @author Aave
 * @notice Implements the base logic for all the actions related to borrowing
 */
library BorrowLogic {
  using ReserveLogic for DataTypes.ReserveCache;
  using ReserveLogic for DataTypes.ReserveData;
  using GPv2SafeERC20 for IERC20;
  using UserConfiguration for DataTypes.UserConfigurationMap;
  using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
  using SafeCast for uint256;

  // See `IPool` for descriptions
  event Borrow(
    address indexed reserve,
    address user,
    address indexed onBehalfOf,
    uint256 amount,
    DataTypes.InterestRateMode interestRateMode,
    uint256 borrowRate,
    uint16 indexed referralCode
  );
  event Repay(
    address indexed reserve,
    address indexed user,
    address indexed repayer,
    uint256 amount,
    bool useATokens
  );
  event RebalanceStableBorrowRate(address indexed reserve, address indexed user);
  event SwapBorrowRateMode(
    address indexed reserve,
    address indexed user,
    DataTypes.InterestRateMode interestRateMode
  );
  event IsolationModeTotalDebtUpdated(address indexed asset, uint256 totalDebt);

  /**
   * @notice Implements the borrow feature. Borrowing allows users that provided collateral to draw liquidity from the
   * Aave protocol proportionally to their collateralization power. For isolated positions, it also increases the
   * isolated debt.
   * @dev  Emits the `Borrow()` event
   * @param reservesData The state of all the reserves
   * @param reservesList The addresses of all the active reserves
   * @param eModeCategories The configuration of all the efficiency mode categories
   * @param userConfig The user configuration mapping that tracks the supplied/borrowed assets
   * @param params The additional parameters needed to execute the borrow function
   */
  function executeBorrow(
    mapping(address => DataTypes.ReserveData) storage reservesData,
    mapping(uint256 => address) storage reservesList,
    mapping(uint8 => DataTypes.EModeCategory) storage eModeCategories,
    DataTypes.UserConfigurationMap storage userConfig,
    DataTypes.ExecuteBorrowParams memory params
  ) public {
    /**
     * @V:E
     * Timeline of writes
     *  1. reserve.cache()              → read storage
        2. reserve.updateState()        → WRITE indexes + timestamp
        3. validateBorrow()             → view-only
        4. debtToken.mint()             → WRITE debt balances
        5. reserve.updateInterestRates()→ WRITE rates
        6. aToken.transferUnderlying() → WRITE liquidity
     */
    DataTypes.ReserveData storage reserve = reservesData[params.asset];
    DataTypes.ReserveCache memory reserveCache = reserve.cache();

    /**
     * @STATE
     * @V:E interest accrual (global state mutation) - this is a PART OF VALIDATION
     * this changes debt indices -> RESERVE CACHE IS UPDATED BECAUSE IN MEMORY!!!,
     * must happen before validation!!!
     * protects invariant - "Interest accrual must be applied before new debt is added"
     * HIGH if this is after validation
     */
    reserve.updateState(reserveCache); 

    /**
     * @V:E risk context derivation - computes *constraints* used by validation!!
     * not a state change
     * reads multiple reserves
     */
    (
      bool isolationModeActive,
      address isolationModeCollateralAddress,
      uint256 isolationModeDebtCeiling
    ) = userConfig.getIsolationModeState(reservesData, reservesList);

    /**
     * @VAL
     * @V:E full borrow eligibility validation (HF, LTV, caps, oracle)
     * this is the single most important block
     * almost all high-severity invariants must be enforced here
     * !! IMPORTANT - IS EVERY CRITICAL INVARIANT ENFORCED HERE, OR ARE SOME ASSUMED?
     */
    ValidationLogic.validateBorrow( 
      reservesData,
      reservesList,
      eModeCategories,
      DataTypes.ValidateBorrowParams({
        reserveCache: reserveCache,
        userConfig: userConfig,
        asset: params.asset,
        userAddress: params.onBehalfOf,
        amount: params.amount,
        interestRateMode: params.interestRateMode,
        maxStableLoanPercent: params.maxStableRateBorrowSizePercent,
        reservesCount: params.reservesCount,
        oracle: params.oracle,
        userEModeCategory: params.userEModeCategory,
        priceOracleSentinel: params.priceOracleSentinel,
        isolationModeActive: isolationModeActive,
        isolationModeCollateralAddress: isolationModeCollateralAddress,
        isolationModeDebtCeiling: isolationModeDebtCeiling
      })
    );

    uint256 currentStableRate = 0;
    bool isFirstBorrowing = false;

    /** ////////////////////////////////////////////////////////// PIVOT POINT IN THE FUNCTION ////////////////////////////////////
     * @V:E irreversible user debt creation (external call)
     * important because: external call
     *                    irreversible
     *                    happens after validation
     *                    happens before underlying transfer
     * AUDITORS INSIGHT:
     * if anything is wrong before this point -> revert saves me
     * if anything is wrong after this -> system must already be safe
     * 
     * 
     * DEBT IS MINTED BEFORE `transferUnderlyingTo()` 
     * Debt token mint = record obligation
     * this ordering enforces this invariant: protocol never gives funds before debt exists
     * @V:E ordering: debt minted before liquidity release (GOOD)
     * @ORDER
     */
    if (params.interestRateMode == DataTypes.InterestRateMode.STABLE) {
      currentStableRate = reserve.currentStableBorrowRate;

      (
        isFirstBorrowing,
        reserveCache.nextTotalStableDebt,
        reserveCache.nextAvgStableBorrowRate
      ) = IStableDebtToken(reserveCache.stableDebtTokenAddress).mint(
        params.user,
        params.onBehalfOf,
        params.amount,
        currentStableRate
      );
    } else {
      (isFirstBorrowing, reserveCache.nextScaledVariableDebt) = IVariableDebtToken(
        reserveCache.variableDebtTokenAddress
      ).mint(params.user, params.onBehalfOf, params.amount, reserveCache.nextVariableBorrowIndex);
    }

    /**
     * @STATE
     * @V:E user borrowing flag update (state mutation)
     * this is not permission enforcement
     * it's accounting / state reflection
     * it's triggered only on first borrow
     * !!! this matters when auditing liquidations and repay
     */
    if (isFirstBorrowing) {
      userConfig.setBorrowing(reserve.id, true);
    }

    /**
     * @V:E isolation mode debt accounting (presicion-sensitive)
     * division + decimals
     * rounding
     * ceiling enforcement relies on this
     * This is a medium-severity bug hotspot historically
     * 
     */
    if (isolationModeActive) {
      uint256 nextIsolationModeTotalDebt = reservesData[isolationModeCollateralAddress]
        .isolationModeTotalDebt += (params.amount /
        10 **
          (reserveCache.reserveConfiguration.getDecimals() -
            ReserveConfiguration.DEBT_CEILING_DECIMALS)).toUint128();
      emit IsolationModeTotalDebtUpdated(
        isolationModeCollateralAddress,
        nextIsolationModeTotalDebt
      );
    }

    /*
       @V:E reserve rate recalculation after borrow
       must reflect the borrow correctly
    */
    reserve.updateInterestRates(
      reserveCache,
      params.asset,
      0,
      params.releaseUnderlying ? params.amount : 0
    );

    /*
      @EXT
      @V:E external call (liquidity release, reentrancy surface)
      ASK: is all validation done?
           is all critical state updated?
           could reentrancy observe broken invarianty? -> investigate

      the flag `releaseUnderlying` is checked because sometimes debt is minted, but underlying in not transferred
    */
    if (params.releaseUnderlying) {
      IAToken(reserveCache.aTokenAddress).transferUnderlyingTo(params.user, params.amount);
    }

    emit Borrow(
      params.asset,
      params.user,
      params.onBehalfOf,
      params.amount,
      params.interestRateMode,
      params.interestRateMode == DataTypes.InterestRateMode.STABLE
        ? currentStableRate
        : reserve.currentVariableBorrowRate,
      params.referralCode
    );
  }

  /**
   * @notice Implements the repay feature. Repaying transfers the underlying back to the aToken and clears the
   * equivalent amount of debt for the user by burning the corresponding debt token. For isolated positions, it also
   * reduces the isolated debt.
   * @dev  Emits the `Repay()` event
   * @param reservesData The state of all the reserves
   * @param reservesList The addresses of all the active reserves
   * @param userConfig The user configuration mapping that tracks the supplied/borrowed assets
   * @param params The additional parameters needed to execute the repay function
   * @return The actual amount being repaid
   */
  function executeRepay(
    mapping(address => DataTypes.ReserveData) storage reservesData,
    mapping(uint256 => address) storage reservesList,
    DataTypes.UserConfigurationMap storage userConfig,
    DataTypes.ExecuteRepayParams memory params
  ) external returns (uint256) {
    DataTypes.ReserveData storage reserve = reservesData[params.asset];
    DataTypes.ReserveCache memory reserveCache = reserve.cache();

    //@V:E updates indices, write to storage
    reserve.updateState(reserveCache);

    //@V:E view - get debts
    (uint256 stableDebt, uint256 variableDebt) = Helpers.getUserCurrentDebt(
      params.onBehalfOf,
      reserveCache
    );

    /* @V:E ACCOUNTING BOUNDARIES?
        here most of invariants should be enforced
    */
    ValidationLogic.validateRepay(
      reserveCache,
      params.amount,
      params.interestRateMode,
      params.onBehalfOf,
      stableDebt,
      variableDebt
    );

    uint256 paybackAmount = params.interestRateMode == DataTypes.InterestRateMode.STABLE
      ? stableDebt
      : variableDebt;

    // Allows a user to repay with aTokens without leaving dust from interest.
    if (params.useATokens && params.amount == type(uint256).max) {
      params.amount = IAToken(reserveCache.aTokenAddress).balanceOf(msg.sender);
    }

    // @V:E reconsider 'paybackAmount'
    if (params.amount < paybackAmount) {
      paybackAmount = params.amount;
    }

    /* @V:E IRREVERSIBLE - pivot point in repay
        here debt tokens are burned - why before transfer?
    */
    if (params.interestRateMode == DataTypes.InterestRateMode.STABLE) {
      (reserveCache.nextTotalStableDebt, reserveCache.nextAvgStableBorrowRate) = IStableDebtToken(
        reserveCache.stableDebtTokenAddress
      ).burn(params.onBehalfOf, paybackAmount);
    } else {
      reserveCache.nextScaledVariableDebt = IVariableDebtToken(
        reserveCache.variableDebtTokenAddress
      ).burn(params.onBehalfOf, paybackAmount, reserveCache.nextVariableBorrowIndex);
    }

    //@V:E update interest rates
    reserve.updateInterestRates(
      reserveCache,
      params.asset,
      params.useATokens ? 0 : paybackAmount,
      0
    );

    // @V:E if user repayed everything, the borrowing flag is zeroed
    if (stableDebt + variableDebt - paybackAmount == 0) {
      userConfig.setBorrowing(reserve.id, false);
    }

    // @V:E calculating debt if isolated mode - what is isolated mode?
    IsolationModeLogic.updateIsolatedDebtIfIsolated(
      reservesData,
      reservesList,
      userConfig,
      reserveCache,
      paybackAmount
    );

    /*@V:E burn ATokens if 'useATokens' is true 
      why burn debt tokens above and A tokens here? what are A tokens?
    */
    if (params.useATokens) {
      IAToken(reserveCache.aTokenAddress).burn(
        msg.sender,
        reserveCache.aTokenAddress,
        paybackAmount,
        reserveCache.nextLiquidityIndex
      );
    } else {
      //@V:E transfer in first
      IERC20(params.asset).safeTransferFrom(msg.sender, reserveCache.aTokenAddress, paybackAmount);

      //@V:E handleRepayment - what is there? burn of debt tokens already done
      IAToken(reserveCache.aTokenAddress).handleRepayment(
        msg.sender,
        params.onBehalfOf,
        paybackAmount
      );
    }

    emit Repay(params.asset, params.onBehalfOf, msg.sender, paybackAmount, params.useATokens);

    return paybackAmount;
  }

  /**
   * @notice Implements the rebalance stable borrow rate feature. In case of liquidity crunches on the protocol, stable
   * rate borrows might need to be rebalanced to bring back equilibrium between the borrow and supply APYs.
   * @dev The rules that define if a position can be rebalanced are implemented in `ValidationLogic.validateRebalanceStableBorrowRate()`
   * @dev Emits the `RebalanceStableBorrowRate()` event
   * @param reserve The state of the reserve of the asset being repaid
   * @param asset The asset of the position being rebalanced
   * @param user The user being rebalanced
   */
  function executeRebalanceStableBorrowRate(
    DataTypes.ReserveData storage reserve,
    address asset,
    address user
  ) external {
    DataTypes.ReserveCache memory reserveCache = reserve.cache();
    reserve.updateState(reserveCache);

    ValidationLogic.validateRebalanceStableBorrowRate(reserve, reserveCache, asset);

    IStableDebtToken stableDebtToken = IStableDebtToken(reserveCache.stableDebtTokenAddress);
    uint256 stableDebt = IERC20(address(stableDebtToken)).balanceOf(user);

    stableDebtToken.burn(user, stableDebt);

    (, reserveCache.nextTotalStableDebt, reserveCache.nextAvgStableBorrowRate) = stableDebtToken
      .mint(user, user, stableDebt, reserve.currentStableBorrowRate);

    reserve.updateInterestRates(reserveCache, asset, 0, 0);

    emit RebalanceStableBorrowRate(asset, user);
  }

  /**
   * @notice Implements the swap borrow rate feature. Borrowers can swap from variable to stable positions at any time.
   * @dev Emits the `Swap()` event
   * @param reserve The of the reserve of the asset being repaid
   * @param userConfig The user configuration mapping that tracks the supplied/borrowed assets
   * @param asset The asset of the position being swapped
   * @param interestRateMode The current interest rate mode of the position being swapped
   */
  function executeSwapBorrowRateMode(
    DataTypes.ReserveData storage reserve,
    DataTypes.UserConfigurationMap storage userConfig,
    address asset,
    DataTypes.InterestRateMode interestRateMode
  ) external {
    DataTypes.ReserveCache memory reserveCache = reserve.cache();

    reserve.updateState(reserveCache);

    (uint256 stableDebt, uint256 variableDebt) = Helpers.getUserCurrentDebt(
      msg.sender,
      reserveCache
    );

    ValidationLogic.validateSwapRateMode(
      reserve,
      reserveCache,
      userConfig,
      stableDebt,
      variableDebt,
      interestRateMode
    );

    if (interestRateMode == DataTypes.InterestRateMode.STABLE) {
      (reserveCache.nextTotalStableDebt, reserveCache.nextAvgStableBorrowRate) = IStableDebtToken(
        reserveCache.stableDebtTokenAddress
      ).burn(msg.sender, stableDebt);

      (, reserveCache.nextScaledVariableDebt) = IVariableDebtToken(
        reserveCache.variableDebtTokenAddress
      ).mint(msg.sender, msg.sender, stableDebt, reserveCache.nextVariableBorrowIndex);
    } else {
      reserveCache.nextScaledVariableDebt = IVariableDebtToken(
        reserveCache.variableDebtTokenAddress
      ).burn(msg.sender, variableDebt, reserveCache.nextVariableBorrowIndex);

      (, reserveCache.nextTotalStableDebt, reserveCache.nextAvgStableBorrowRate) = IStableDebtToken(
        reserveCache.stableDebtTokenAddress
      ).mint(msg.sender, msg.sender, variableDebt, reserve.currentStableBorrowRate);
    }

    reserve.updateInterestRates(reserveCache, asset, 0, 0);

    emit SwapBorrowRateMode(asset, msg.sender, interestRateMode);
  }
}
