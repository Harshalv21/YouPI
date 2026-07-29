-- ═══════════════════════════════════════════════════════════
-- V14: Recharge plan validity + computed expiry date
-- ═══════════════════════════════════════════════════════════
-- Needed for the home screen "Active Recharge" card to show a real
-- status + end date instead of a static placeholder. Neither
-- plan_validity_days nor an expiry date were ever captured anywhere --
-- CreateRechargeRequest didn't carry validity through from the plan the
-- user picked, so there was no way to compute when a recharge expires.
--
-- Numbered V14 because a teammate's V13 (gold_wallet coin-model
-- migration, see YouPI_GoldCoin_Status_Report.pdf) is already applied on
-- production. Confirm this is still the correct next number after your
-- next `git pull` before running it -- don't just trust this file blindly
-- if more migrations have landed since.

ALTER TABLE recharge_orders
    ADD COLUMN plan_validity_days SMALLINT,
    ADD COLUMN expiry_date DATE;

-- Only meaningful once a recharge actually succeeds -- index supports the
-- "find my current active recharge" query (most recent RECHARGE_SUCCESS
-- order for this user where expiry_date hasn't passed yet).
CREATE INDEX idx_recharge_active_lookup
    ON recharge_orders (user_id, status, expiry_date DESC);