-- ═══════════════════════════════════════════════════════════
-- V3: Wallets + Immutable Double-Entry Ledger (PostgreSQL)
-- ═══════════════════════════════════════════════════════════

CREATE TABLE wallets (
    id          UUID NOT NULL DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL,
    wallet_type VARCHAR(20) NOT NULL,
    balance     DECIMAL(15,2) NOT NULL DEFAULT 0.00,
    currency    VARCHAR(5) NOT NULL DEFAULT 'INR',
    is_active   BOOLEAN NOT NULL DEFAULT true,
    created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    CONSTRAINT uq_user_wallet UNIQUE (user_id, wallet_type),
    CONSTRAINT fk_wallet_user FOREIGN KEY (user_id) REFERENCES users(id),
    CONSTRAINT chk_wallet_type CHECK (wallet_type IN ('NBFC','SMART_SAVER','GOLD','FD_COLLATERAL')),
    CONSTRAINT chk_wallet_balance CHECK (balance >= 0)
);

CREATE INDEX idx_wallet_user ON wallets(user_id, wallet_type);

/* Immutable double-entry ledger — NEVER UPDATE, only INSERT */
CREATE TABLE ledger_entries (
    id              UUID NOT NULL DEFAULT gen_random_uuid(),
    wallet_id       UUID NOT NULL,
    txn_direction   VARCHAR(6) NOT NULL,
    amount          DECIMAL(15,2) NOT NULL,
    balance_before  DECIMAL(15,2) NOT NULL,
    balance_after   DECIMAL(15,2) NOT NULL,
    reference_type  VARCHAR(40) NOT NULL,
    reference_id    UUID,
    description     TEXT,
    idempotency_key VARCHAR(100),
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    CONSTRAINT uq_ledger_idempotency UNIQUE (idempotency_key),
    CONSTRAINT fk_ledger_wallet FOREIGN KEY (wallet_id) REFERENCES wallets(id),
    CONSTRAINT chk_txn_direction CHECK (txn_direction IN ('CREDIT','DEBIT')),
    CONSTRAINT chk_ledger_amount CHECK (amount > 0)
);

CREATE INDEX idx_ledger_wallet_time ON ledger_entries(wallet_id, created_at);
CREATE INDEX idx_ledger_ref ON ledger_entries(reference_type, reference_id);