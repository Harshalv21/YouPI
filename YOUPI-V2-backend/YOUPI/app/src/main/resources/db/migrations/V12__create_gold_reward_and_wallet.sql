-- V12__create_gold_reward_and_wallet.sql

-- 1. Reward ledger — har recharge se mila reward track karega
CREATE TABLE gold_reward_ledger (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL,
    recharge_txn_id VARCHAR(128) NOT NULL,
    recharge_amount NUMERIC(12,2) NOT NULL,
    reward_value_rupees NUMERIC(12,2) NOT NULL,      -- 1% of recharge_amount
    gold_rate_at_credit NUMERIC(12,4) NOT NULL,       -- Augmont rate used at credit time
    gold_grams NUMERIC(14,6) NOT NULL,                -- reward_value_rupees / gold_rate_at_credit
    status VARCHAR(20) NOT NULL DEFAULT 'CREDITED',   -- CREDITED, REVERSED
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT uq_recharge_txn UNIQUE (recharge_txn_id)   -- idempotency: ek recharge = ek hi reward
);

CREATE INDEX idx_gold_reward_user ON gold_reward_ledger(user_id);

-- 2. User's gold wallet — running balance (grams)
CREATE TABLE gold_wallet (
    user_id UUID PRIMARY KEY,
    total_grams NUMERIC(14,6) NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. Withdraw requests — rupee-based, min ₹50
CREATE TABLE gold_withdraw_requests (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL,
    amount_rupees NUMERIC(12,2) NOT NULL,
    gold_grams_deducted NUMERIC(14,6) NOT NULL,
    gold_rate_at_withdraw NUMERIC(12,4) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING',    -- PENDING, COMPLETED, FAILED
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT chk_min_withdraw CHECK (amount_rupees >= 50)
);

CREATE INDEX idx_gold_withdraw_user ON gold_withdraw_requests(user_id);