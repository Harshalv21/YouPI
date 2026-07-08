-- ═══════════════════════════════════════════════════════════
-- V7: Investments — Digital Gold + Fixed Deposits (PostgreSQL)
-- ═══════════════════════════════════════════════════════════

-- ── Gold Holdings ──
CREATE TABLE gold_holdings (
    id               CHAR(36) NOT NULL DEFAULT gen_random_uuid()::text,
    user_id          CHAR(36) NOT NULL,
    total_grams      DECIMAL(14,6) NOT NULL DEFAULT 0.000000,
    total_invested   DECIMAL(15,2) NOT NULL DEFAULT 0.00,
    gold_provider    VARCHAR(30) NOT NULL DEFAULT 'SAFEGOLD',
    provider_user_id VARCHAR(100),
    updated_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    CONSTRAINT uq_gold_user UNIQUE (user_id),
    CONSTRAINT fk_gold_user FOREIGN KEY (user_id) REFERENCES users(id),
    CONSTRAINT chk_gold_grams CHECK (total_grams >= 0)
);

-- ── Gold Transactions ──
CREATE TABLE gold_transactions (
    id                CHAR(36) NOT NULL DEFAULT gen_random_uuid()::text,
    user_id           CHAR(36) NOT NULL,
    txn_type          VARCHAR(20) NOT NULL,
    amount_inr        DECIMAL(12,2) NOT NULL,
    grams             DECIMAL(14,6) NOT NULL,
    rate_per_gram     DECIMAL(10,2) NOT NULL,
    provider_txn_id   VARCHAR(100),
    status            VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    triggered_by      VARCHAR(30) NOT NULL,
    recharge_order_id CHAR(36),
    idempotency_key   VARCHAR(100) NOT NULL,
    created_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    CONSTRAINT uq_gold_txn_idempotency UNIQUE (idempotency_key),
    CONSTRAINT fk_gold_txn_user FOREIGN KEY (user_id) REFERENCES users(id),
    CONSTRAINT fk_gold_txn_recharge FOREIGN KEY (recharge_order_id) REFERENCES recharge_orders(id),
    CONSTRAINT chk_gold_txn_type CHECK (txn_type IN ('BUY','SELL','SGB')),
    CONSTRAINT chk_gold_txn_amount CHECK (amount_inr > 0),
    CONSTRAINT chk_gold_txn_grams CHECK (grams > 0),
    CONSTRAINT chk_gold_txn_status CHECK (status IN ('PENDING','SUCCESS','FAILED','REVERSED')),
    CONSTRAINT chk_gold_triggered CHECK (triggered_by IN ('MANUAL','RECHARGE_AUTO','SIP'))
);

CREATE INDEX idx_gold_txn_user ON gold_transactions(user_id, created_at);
CREATE INDEX idx_gold_txn_status ON gold_transactions(status);

-- ── Gold Price Snapshots (time-series) ──
CREATE TABLE gold_price_snapshots (
    id                BIGSERIAL PRIMARY KEY,
    rate_24k_per_gram DECIMAL(10,2) NOT NULL,
    provider          VARCHAR(30) NOT NULL DEFAULT 'SAFEGOLD',
    recorded_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_gold_price_time ON gold_price_snapshots(recorded_at);

-- ── Fixed Deposits ──
CREATE TABLE fixed_deposits (
    id              CHAR(36) NOT NULL DEFAULT gen_random_uuid()::text,
    user_id         CHAR(36) NOT NULL,
    principal       DECIMAL(12,2) NOT NULL,
    interest_rate   DECIMAL(5,2) NOT NULL,
    tenure_months   SMALLINT NOT NULL,
    maturity_date   DATE NOT NULL,
    maturity_amount DECIMAL(12,2) NOT NULL,
    bank_partner    VARCHAR(50) NOT NULL DEFAULT 'AXIS_BANK',
    bank_fd_ref     VARCHAR(100),
    overdraft_limit DECIMAL(12,2) GENERATED ALWAYS AS (principal * 0.80) STORED,
    status          VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    CONSTRAINT fk_fd_user FOREIGN KEY (user_id) REFERENCES users(id),
    CONSTRAINT chk_fd_principal CHECK (principal >= 1000),
    CONSTRAINT chk_fd_tenure CHECK (tenure_months IN (3,6,12,24,36)),
    CONSTRAINT chk_fd_status CHECK (status IN ('ACTIVE','MATURED','PREMATURE_CLOSED'))
);

CREATE INDEX idx_fd_user ON fixed_deposits(user_id, status);
