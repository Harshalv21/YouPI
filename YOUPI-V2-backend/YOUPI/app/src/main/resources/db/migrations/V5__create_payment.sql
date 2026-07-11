-- ═══════════════════════════════════════════════════════════
-- V5: Payment Orders — Razorpay (PostgreSQL)
-- ═══════════════════════════════════════════════════════════

CREATE TABLE payment_orders (
    id                  UUID NOT NULL DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL,
    razorpay_order_id   VARCHAR(100) NOT NULL,
    razorpay_payment_id VARCHAR(100),
    razorpay_signature  VARCHAR(300),
    amount_paise        BIGINT NOT NULL,
    currency            VARCHAR(5) NOT NULL DEFAULT 'INR',
    purpose             VARCHAR(40) NOT NULL,
    reference_id        UUID,
    status              VARCHAR(20) NOT NULL DEFAULT 'CREATED',
    webhook_event       VARCHAR(60),
    webhook_payload     JSONB,
    idempotency_key     VARCHAR(100) NOT NULL,
    created_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    CONSTRAINT uq_payment_razorpay UNIQUE (razorpay_order_id),
    CONSTRAINT uq_payment_idempotency UNIQUE (idempotency_key),
    CONSTRAINT fk_payment_user FOREIGN KEY (user_id) REFERENCES users(id),
    CONSTRAINT chk_payment_amount CHECK (amount_paise > 0),
    CONSTRAINT chk_payment_purpose CHECK (purpose IN
        ('RECHARGE','SMART_DEPOSIT','FD_OPEN','LOAN_EMI','GOLD_BUY','WALLET_TOPUP')),
    CONSTRAINT chk_payment_status CHECK (status IN
        ('CREATED','CAPTURED','FAILED','REFUNDED','DISPUTED'))
);

CREATE INDEX idx_payment_user ON payment_orders(user_id, created_at);
CREATE INDEX idx_payment_razorpay ON payment_orders(razorpay_order_id);
CREATE INDEX idx_payment_status ON payment_orders(status);
CREATE INDEX idx_payment_purpose_ref ON payment_orders(purpose, reference_id);