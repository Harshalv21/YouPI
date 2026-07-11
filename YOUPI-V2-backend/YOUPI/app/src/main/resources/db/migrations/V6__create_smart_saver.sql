-- ═══════════════════════════════════════════════════════════
-- V6: Smart Saver Allocations (PostgreSQL)
-- Note: PostgreSQL uses GENERATED ALWAYS AS for computed columns
-- ═══════════════════════════════════════════════════════════

CREATE TABLE smart_saver_allocations (
    id                UUID NOT NULL DEFAULT gen_random_uuid(),
    user_id           UUID NOT NULL,
    deposit_amount    DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    admin_seed_amount DECIMAL(10,2) NOT NULL DEFAULT 1000.00,
    total_collateral  DECIMAL(10,2) GENERATED ALWAYS AS (deposit_amount + admin_seed_amount) STORED,
    credit_limit      DECIMAL(10,2) GENERATED ALWAYS AS ((deposit_amount + admin_seed_amount) * 0.80) STORED,
    used_credit       DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    available_credit  DECIMAL(10,2) GENERATED ALWAYS AS (((deposit_amount + admin_seed_amount) * 0.80) - used_credit) STORED,
    status            VARCHAR(20) NOT NULL DEFAULT 'PENDING_ACTIVATION',
    activated_by      UUID,
    activated_at      TIMESTAMP NULL,
    notes             TEXT,
    created_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    CONSTRAINT uq_ss_user UNIQUE (user_id),
    CONSTRAINT fk_ss_user FOREIGN KEY (user_id) REFERENCES users(id),
    CONSTRAINT fk_ss_activator FOREIGN KEY (activated_by) REFERENCES users(id),
    CONSTRAINT chk_ss_status CHECK (status IN
        ('PENDING_ACTIVATION','ACTIVE','SUSPENDED','EXHAUSTED'))
);

CREATE INDEX idx_ss_alloc_user ON smart_saver_allocations(user_id);
CREATE INDEX idx_ss_alloc_status ON smart_saver_allocations(status);