// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/*
        Invariant_3 - repay() must revert if effective user debt is zero
 */

import {Test, console} from "forge-std/Test.sol";
import {ValidationLogic} from "../../contracts/protocol/libraries/logic/ValidationLogic.sol";
import {DataTypes} from "../../contracts/protocol/libraries/types/DataTypes.sol";
import {Errors} from "../../contracts/protocol/libraries/helpers/Errors.sol";

contract Invariant_3 is Test {
    DataTypes.ReserveCache reserveCache;
    DataTypes.ReserveConfigurationMap reserveConfigurationActiveNotPaused;
    uint256 amountSent = 5;
    DataTypes.InterestRateMode stableInterestRateMode = DataTypes.InterestRateMode.STABLE;
    DataTypes.InterestRateMode variableInterestRateMode = DataTypes.InterestRateMode.VARIABLE;

    address onBehalfOf = makeAddr("onBehalfOf");
    uint256 stableDebt = 0;
    uint256 variableDebt = 0;

    function setUp() public{
        reserveConfigurationActiveNotPaused = DataTypes.ReserveConfigurationMap({
            data: (1<<56)
        });

        reserveCache = DataTypes.ReserveCache({
            currScaledVariableDebt: 0,
            nextScaledVariableDebt: 0,
            currPrincipalStableDebt: 0,
            currAvgStableBorrowRate: 0,
            currTotalStableDebt: 0,
            nextAvgStableBorrowRate: 0,
            nextTotalStableDebt: 0,
            currLiquidityIndex: 0,
            nextLiquidityIndex: 0,
            currVariableBorrowIndex: 0,
            nextVariableBorrowIndex: 0,
            currLiquidityRate: 0,
            currVariableBorrowRate: 0,
            reserveFactor: 0,
            reserveConfiguration: reserveConfigurationActiveNotPaused,
            aTokenAddress: makeAddr("aTokenAddress"),
            stableDebtTokenAddress: makeAddr("stableDebtTokenAddress"),
            variableDebtTokenAddress: makeAddr("variableDebtTokenAddress"),
            reserveLastUpdateTimestamp: 0,
            stableDebtLastUpdateTimestamp: 0
        });

    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_unit_revertIfRepayZeroDebt_stableDebt() public {
        vm.expectRevert(abi.encode(Errors.NO_DEBT_OF_SELECTED_TYPE));
        ValidationLogic.validateRepay(reserveCache, amountSent, stableInterestRateMode, onBehalfOf, stableDebt, variableDebt);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_unit_revertIfRepayZeroDebt_variableDebt() public {
        vm.expectRevert(abi.encode(Errors.NO_DEBT_OF_SELECTED_TYPE));
        ValidationLogic.validateRepay(reserveCache, amountSent, variableInterestRateMode, onBehalfOf, stableDebt, variableDebt);
    }
}