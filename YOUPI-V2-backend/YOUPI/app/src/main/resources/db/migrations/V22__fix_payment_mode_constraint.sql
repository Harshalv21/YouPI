-- BUG FIX: V21 added wallet_amount/gateway_amount columns for SPLIT payment
-- mode, but chk_payment_mode constraint was never updated to allow 'WALLET'
-- or 'SPLIT' as valid payment_mode values. This caused every WALLET-mode
-- and SPLIT-mode recharge order insert to fail with:
--   "new row for relation recharge_orders violates check constraint chk_payment_mode"
--
-- Wallet debit happens BEFORE this insert in RechargeService.kt, so the
-- failure left users with a debited wallet and no recharge_orders row at
-- all (undiscoverable by reconcileStuckSplitOrders(), which only scans
-- existing recharge_orders rows). See Aug 21 incident: userId
-- fa516d42-74fe-4ff7-8179-cfbb5d213f0b, mobile 9867123027, manually reversed.

ALTER TABLE recharge_orders DROP CONSTRAINT chk_payment_mode;

ALTER TABLE recharge_orders ADD CONSTRAINT chk_payment_mode CHECK (payment_mode IN
    ('FULL','EMI_3','EMI_6','EMI_12','SMART_SAVER_WALLET','WALLET','SPLIT'));