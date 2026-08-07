-- ═══════════════════════════════════════════════════════════
-- V17: Wallet MVP -- extend existing payment_orders (V5) + Phase 2 stub tables
--
-- CORRECTION: payment_orders already exists (V5__create_payment.sql).
-- It's a generic, purpose-driven table -- 'WALLET_TOPUP' is already an
-- allowed `purpose` value. Wallet top-up orders reuse THIS table
-- (row: purpose='WALLET_TOPUP', reference_id=wallet_id), not a new one.
-- We only ALTER it here to add the fields the webhook handler and
-- sweeper job need. Column names stay Razorpay-flavoured for
-- backward-compat with existing recharge/gold rows and code
-- (razorpay_order_id / razorpay_payment_id already carry Cashfree's
-- order/payment ids post-migration -- see PaymentService.kt).
--
-- reward_grant / float_position / settlement_allocation: Phase 2
-- schema, created now so Phase 2 only needs new service logic, not a
-- data migration (Option 3 -- hybrid approach, per MVP Implementation
-- Brief). These stay unused / empty until Phase 2 work begins --
-- do not wire any service code against them in this MVP.
-- ═══════════════════════════════════════════════════════════

-- ── Extend existing payment_orders (LIVE -- wired in this MVP) ──

ALTER TABLE payment_orders
    ADD COLUMN IF NOT EXISTS payment_session_id VARCHAR(120),
    ADD COLUMN IF NOT EXISTS failure_reason     VARCHAR(255),
    ADD COLUMN IF NOT EXISTS paid_at            TIMESTAMP;

-- Verified against pg_constraint before deploy: constraint name is
-- chk_payment_status (matches V5__create_payment.sql). Plain drop/add
-- is enough here -- single Flyway-controlled project, every
-- environment shares the same migration history.
ALTER TABLE payment_orders
    DROP CONSTRAINT chk_payment_status;

ALTER TABLE payment_orders
    ADD CONSTRAINT chk_payment_status CHECK (status IN
        ('CREATED','PENDING','CAPTURED','FAILED','REFUNDED','DISPUTED'));

-- Note: no new index on idempotency_key -- uq_payment_idempotency
-- (V5) is a UNIQUE constraint and already provides one.

-- ── Phase 2 stubs (created now, UNUSED until Phase 2) ──

-- REWARD bucket cashback grants (Phase 2: REWARD wallet type)
CREATE TABLE reward_grant (
    id              UUID NOT NULL DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL,
    wallet_id       UUID NOT NULL,
    amount          DECIMAL(15,2) NOT NULL,
    reason          VARCHAR(40) NOT NULL,
    reference_type  VARCHAR(40),
    reference_id    UUID,
    status          VARCHAR(20) NOT NULL DEFAULT 'GRANTED',
    granted_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at      TIMESTAMP,
    PRIMARY KEY (id),
    CONSTRAINT fk_reward_grant_user FOREIGN KEY (user_id) REFERENCES users(id),
    CONSTRAINT fk_reward_grant_wallet FOREIGN KEY (wallet_id) REFERENCES wallets(id),
    CONSTRAINT chk_reward_grant_amount CHECK (amount > 0),
    CONSTRAINT chk_reward_grant_status CHECK (status IN ('GRANTED','EXPIRED','REVOKED')),
    CONSTRAINT chk_reward_grant_reason CHECK (reason IN ('CASHBACK','REFERRAL','BONUS','PROMOTION'))
);

-- Treasury / float coverage monitoring (Phase 2)
CREATE TABLE float_position (
    id                  UUID NOT NULL DEFAULT gen_random_uuid(),
    wallet_type         VARCHAR(20) NOT NULL,
    total_liability      DECIMAL(18,2) NOT NULL DEFAULT 0.00,
    bank_float_balance  DECIMAL(18,2) NOT NULL DEFAULT 0.00,
    coverage_ratio      DECIMAL(6,4),
    recorded_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    CONSTRAINT chk_float_position_wallet_type CHECK (wallet_type IN ('NBFC','REWARD')),
    CONSTRAINT chk_float_position_coverage_ratio CHECK (coverage_ratio IS NULL OR coverage_ratio >= 0)
);

-- Split payment (wallet + PG) settlement allocation (Phase 2)
CREATE TABLE settlement_allocation (
    id                  UUID NOT NULL DEFAULT gen_random_uuid(),
    order_reference_id  UUID NOT NULL,
    wallet_id           UUID,
    payment_order_id    UUID,
    allocated_amount    DECIMAL(15,2) NOT NULL,
    allocation_type     VARCHAR(20) NOT NULL,
    created_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    CONSTRAINT fk_settlement_wallet FOREIGN KEY (wallet_id) REFERENCES wallets(id),
    CONSTRAINT fk_settlement_payment_order FOREIGN KEY (payment_order_id) REFERENCES payment_orders(id),
    CONSTRAINT chk_settlement_amount CHECK (allocated_amount > 0),
    CONSTRAINT chk_settlement_allocation_type CHECK (allocation_type IN ('WALLET','GATEWAY'))
);