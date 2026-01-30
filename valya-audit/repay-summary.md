# FEATURE AUDIT - AAVE-V3 `REPAY()`

# Feature scope
1. The feature under the audit: `repay()`.
2. Economic purpose: it allows to repay user debt (partially or totally) for users themself or on behalf of users provided that they were explicitly delegated. Protocol can accept more assets than remaining debt at the call boundary, but must cap effective repay to outstanding debt and refund excesses.
3. State modified: 
    * protocol liquidity, 
    * total debt amount, 
    * user debt balances and borrowing configuration

# Invariants (grouped)
## 1. Pre-state (before repay)
* STATE VALIDITY: user debt >= 0.
* STATE VALIDITY: if user debt == 0, repay must revert.
* PROTOCOL-LEVEL SAFETY: reserve should not be pauzed or frozen
* DEPENDENCY SAFETY: repay() must not rely on oracle values for correctness - THIS IS A NEGATIVE INVARIANT!

## 2. Mid-process (during repay)
* ATOMICITY: debt burn and liquidity increase must be atomic - no observable state where one happens without the other.
* AUTHORIZATION: only debtor or approved delegate can repay on behalf.
* NON-RESTRICTIVENESS: any third party may repay their own funds for a debtor if explicitly allowed by protocol design

## 3. Post-state (after repay)
* PROTOCOL SOLVENCY: transferred repay amount to protocol (effective repay amount) <= user debt
* PROTOCOL SOLVENCY: net reserve liquidity increase == effective repay amount.
* PROTOCOL SOLVENCY: user debt token burn amount == transferred repay amount to protocol
* INDEX CONSISTENCY: indices may update, but must remain monotonic and consistent with accrued interest.
* INDEX CONSISTENCY: reserve indices are monotonic non-decreasing and independent of individual user repay actions.
* INDEX CONSISTENCY: a user's debt exposure is fully eliminated when scaled debt becomes zero, without mutating reserve indices.
* DUST SAFETY: protocol must not create unrepayable or irreducible debt dust.
* ACCOUNTING: user health factor must never decrease as a result of 'repay()'
* ACCOUNTING: user state is updated correctly on full repay

# Failure Surface
If this feature fails, how does the protocol lose money?

* Liquidity-free debt burn (user debt tokens burn without protocol liquidity increase) -> ATOMICITY/CONSERVATION INVARIANT BROKEN,
* Indices decrease -> INDEX CONSISTENCY INVARIANT IS BROKEN,
* Unauthorized debt repay -> AUTHORIZATION INVARIANT BROKEN,
* Health factor improves without protocol liquidity increase -> ACCOUNTING CONSERVATION BROKEN,
* Health factor decreases as a result on 'repay()' -> ACCOUNTING CONSERVATION BROKEN
* Oracle-based under-repay -> DEPENDENCY SAFETY BROKEN,
* Persistent dust debt -> DUST SAFETY INVARIANT BROKEN.

# Table of Invariants + Failure Surface
<!--> Comprose a table in google drive. Paste an image of a table here <!-->

# Cross-Feature Invariant Consistency
`repay()` should reverse all borrow-induced state changes: decrease debt tokens and restore liquidity, should reverse principal effects, not necessarily index history.




