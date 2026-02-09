// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/*
        Invariant_2 - reserve should be active and asset is not paused
 */

import {Test, console} from "forge-std/Test.sol";
import {ValidationLogic} from "../../contracts/protocol/libraries/logic/ValidationLogic.sol";
import {DataTypes} from "../../contracts/protocol/libraries/types/DataTypes.sol";
import {Errors} from "../../contracts/protocol/libraries/helpers/Errors.sol";

contract Invariant_2 is Test {
    DataTypes.ReserveCache reserveCache;
    DataTypes.ReserveConfigurationMap reserveConfigurationActivePaused;
    DataTypes.ReserveConfigurationMap reserveConfigurationNotActiveNotPaused;
    DataTypes.ReserveConfigurationMap reserveConfigurationActiveNotPaused;
    uint256 amountSent = 5;
    DataTypes.InterestRateMode interestRateMode = DataTypes.InterestRateMode.STABLE;
    address onBehalfOf = makeAddr("onBehalfOf");
    uint256 stableDebt = 1;
    uint256 variableDebt = 1;

    function setUp() public{
        reserveConfigurationActivePaused = DataTypes.ReserveConfigurationMap({
            data: (1<<56) | (1<<60)
        });

        reserveConfigurationNotActiveNotPaused = DataTypes.ReserveConfigurationMap({
            data: 0
        });

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
            reserveConfiguration: reserveConfigurationNotActiveNotPaused,
            aTokenAddress: makeAddr("aTokenAddress"),
            stableDebtTokenAddress: makeAddr("stableDebtTokenAddress"),
            variableDebtTokenAddress: makeAddr("variableDebtTokenAddress"),
            reserveLastUpdateTimestamp: 0,
            stableDebtLastUpdateTimestamp: 0
        });

    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_unit_validateRepay_revertsIfReserveIsPaused() public {
        reserveCache.reserveConfiguration = reserveConfigurationActivePaused;
        vm.expectRevert(abi.encode(Errors.RESERVE_PAUSED));
        ValidationLogic.validateRepay(reserveCache, amountSent, interestRateMode, onBehalfOf, stableDebt, variableDebt);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_unit_validateRepay_revertsIfAssetIsInactive() public {
        reserveCache.reserveConfiguration = reserveConfigurationNotActiveNotPaused;
        vm.expectRevert(abi.encode(Errors.RESERVE_INACTIVE));
        ValidationLogic.validateRepay(reserveCache, amountSent, interestRateMode, onBehalfOf, stableDebt, variableDebt);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_unit_validateRepay_noRevertIfReserveIsNotPausedAndAssetActive() public {
        reserveCache.reserveConfiguration = reserveConfigurationActiveNotPaused;
        ValidationLogic.validateRepay(reserveCache, amountSent, interestRateMode, onBehalfOf, stableDebt, variableDebt);
    }
}