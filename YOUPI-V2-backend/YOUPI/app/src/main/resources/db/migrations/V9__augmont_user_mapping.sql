-- ═══════════════════════════════════════════════════════════
-- V9: Augmont Integration — User mapping + Gold transaction columns (PostgreSQL)
-- ═══════════════════════════════════════════════════════════

-- ── Augmont User Mappings ──
-- Maps each YouPI user to their Augmont merchant-user identity
CREATE TABLE augmont_user_mappings (
    id                  UUID NOT NULL DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL,
    augmont_unique_id   VARCHAR(100) NOT NULL,  -- Augmont uniqueId returned on user creation
    augmont_user_name   VARCHAR(200),
    kyc_status          VARCHAR(30) NOT NULL DEFAULT 'PENDING',
    created_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    CONSTRAINT uq_augmont_user UNIQUE (user_id),
    CONSTRAINT uq_augmont_unique_id UNIQUE (augmont_unique_id),
    CONSTRAINT fk_augmont_user FOREIGN KEY (user_id) REFERENCES users(id)
);

-- ── Add Augmont-specific columns to gold_transactions ──
ALTER TABLE gold_transactions
    ADD COLUMN augmont_txn_id VARCHAR(100),
    ADD COLUMN block_id       VARCHAR(100),
    ADD COLUMN metal_type     VARCHAR(10) NOT NULL DEFAULT 'GOLD';

-- Update gold_provider default to AUGMONT for new holdings
ALTER TABLE gold_holdings
    ALTER COLUMN gold_provider SET DEFAULT 'AUGMONT';

-- Update existing gold_transactions CHECK to include SELL_SILVER/BUY_SILVER
ALTER TABLE gold_transactions
    DROP CONSTRAINT chk_gold_txn_type;

ALTER TABLE gold_transactions
    ADD CONSTRAINT chk_gold_txn_type CHECK (txn_type IN ('BUY','SELL','SGB'));