-- ═══════════════════════════════════════════════════════════
-- V13: Simplify Gold Reward to Coin-Count + Rupees (no Augmont/grams yet)
-- ═══════════════════════════════════════════════════════════

-- 1. Drop old grams-based gold_wallet structure, recreate as coin+rupees based
DROP TABLE IF EXISTS gold_wallet;

CREATE TABLE gold_wallet (
    user_id UUID PRIMARY KEY,
    coin_count INT NOT NULL DEFAULT 0,
    balance_rupees NUMERIC(12,2) NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. Reward ledger — one row per eligible recharge (audit trail)
CREATE TABLE IF NOT EXISTS gold_reward_ledger (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL,
    recharge_txn_id VARCHAR(128) NOT NULL,
    recharge_amount NUMERIC(12,2) NOT NULL,
    reward_value_rupees NUMERIC(12,2) NOT NULL,   -- 1% of recharge_amount
    status VARCHAR(20) NOT NULL DEFAULT 'CREDITED',   -- CREDITED, REVERSED
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT uq_recharge_txn UNIQUE (recharge_txn_id)   -- idempotency
);

CREATE INDEX IF NOT EXISTS idx_gold_reward_user ON gold_reward_ledger(user_id);

-- 3. gold_withdraw_requests already correct from V12 (rupees-based, min ₹50) — no change needed