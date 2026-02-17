borrow()
    |-> BorrowLogic.executeBorrow()
        |-> CACHE: reserve.cache()
        |-> STORAGE MUTATED / MUTATION CLUSTER - UPDATE RESERVE STATE: reserve.updateState()
        |-> VIEW: userConfig.getIsolationModeState()
        |-> EXTERNAL CALL: ValidationLogic.validateBorrow()
        |-> if stableMode
            |-> EXTERNAL CALL / MUTATION CLUSTER - UPDATE USER AND RESERVE DEBT: IStableDebtToken.mint()
        |-> else
            |-> EXTERNAL CALL / MUTATION CLUSTER - UPDATE USER AND RESERVE DEBT: IVariableDebtToken.mint()
        |-> STORAGE MUTATED / MUTATION CLUSTER - UPDATE USER STATE: userConfig.setBorrowing()
        |-> if isolationModeActive
            |-> EMIT IsolationModeTotalDebtUpdated()
        |-> STORAGE MUTATED / MUTATION CLUSTER - UPDATE INDICES AND RESERVE STATE: reserve.updateInterestRates()
        |-> if releaseUnderlying
            |-> EXTERNAL CALL / CONTROL JUMP / MUTATION CLUSTER - TRANSFER: IAToken.transferUnderlyingTo()
        |-> EMIT Borrow()

The following structure crystallizes past interest before minting new debt:
-> reserve.updateState() - updates timestamp
    -> _updateIndexes() - updates reserve indeces (liquidityIndex and variableBorrowIndes - current and next are different now)
    -> _accrueToTreasury() - (totalDebtAccrued * reserveFactor) = some percent from additional debt that is created by current borrow; divide it by liquidityIndex and accrue the result to treasury - where do this assets go later?
-> mint debt
-> userConfig.setBorrowing() - updates user config
-> reserve.updateInterestRates()
-> transferUnderlyingTo

What it mutates and the Core Economic Action:
1. The borrow() function mutates reserve state, user debt state, user configuration, and triggers liquidity transfer. The core economic action is converting reserve liquidity into indexed user debt while repricing the pool.

2. The core economic action is not 'borrow accrues interest'.

It is important to correctly specify economic action for alpha design because:
- In the case of the core action is "borrow accrues interest" - the alpha will be designed around yeild.
- In the case of the core action is "borrow mints indexed liabilities and reprices liquidity" - the alpha will be designed around:
  - timing of state updates
  - index synchronization
  - repricing effects
  - liquidity shocks

The most important insight of Day 1:
1. Borrow is not "giving tokens"
2. Borrow is
   1. synchronizing reserve time state
   2. minting indexed liability
   3. repricing the pool
   4. then releasing liquidity
3. Debt creation before liquidity release