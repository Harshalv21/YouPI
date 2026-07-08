-- ═══════════════════════════════════════════════════════════
-- V4: Recharge Orders + EMI Schedules (PostgreSQL)
-- ═══════════════════════════════════════════════════════════

CREATE TABLE recharge_orders (
    id                   CHAR(36) NOT NULL DEFAULT gen_random_uuid()::text,
    user_id              CHAR(36) NOT NULL,
    mobile_number        VARCHAR(13) NOT NULL,
    operator             VARCHAR(30) NOT NULL,
    circle               VARCHAR(50),
    plan_id              VARCHAR(100),
    plan_amount          DECIMAL(8,2) NOT NULL,
    plan_details         JSONB NOT NULL DEFAULT '{}',
    payment_mode         VARCHAR(25) NOT NULL,
    emi_months           SMALLINT,
    emi_amount           DECIMAL(8,2),
    status               VARCHAR(25) NOT NULL DEFAULT 'INITIATED',
    razorpay_order_id    VARCHAR(100),
    razorpay_payment_id  VARCHAR(100),
    a1topup_txn_id       VARCHAR(100),
    a1topup_status       VARCHAR(30),
    a1topup_raw_response JSONB,
    failure_reason       TEXT,
    gold_auto_invest     BOOLEAN NOT NULL DEFAULT false,
    gold_txn_id          CHAR(36),
    idempotency_key      VARCHAR(100) NOT NULL,
    created_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    CONSTRAINT uq_recharge_idempotency UNIQUE (idempotency_key),
    CONSTRAINT fk_recharge_user FOREIGN KEY (user_id) REFERENCES users(id),
    CONSTRAINT chk_payment_mode CHECK (payment_mode IN
        ('FULL','EMI_3','EMI_6','EMI_12','SMART_SAVER_WALLET')),
    CONSTRAINT chk_recharge_status CHECK (status IN
        ('INITIATED','PAYMENT_DONE','RECHARGE_PENDING','RECHARGE_SUCCESS','RECHARGE_FAILED','REFUNDED'))
);

CREATE INDEX idx_recharge_user_time ON recharge_orders(user_id, created_at);
CREATE INDEX idx_recharge_status ON recharge_orders(status);
CREATE INDEX idx_recharge_a1topup ON recharge_orders(a1topup_txn_id);

CREATE TABLE recharge_emi_schedules (
    id                  CHAR(36) NOT NULL DEFAULT gen_random_uuid()::text,
    recharge_id         CHAR(36) NOT NULL,
    user_id             CHAR(36) NOT NULL,
    instalment_no       SMALLINT NOT NULL,
    due_date            DATE NOT NULL,
    amount              DECIMAL(8,2) NOT NULL,
    status              VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    paid_at             TIMESTAMP NULL,
    razorpay_payment_id VARCHAR(100),
    created_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    CONSTRAINT uq_recharge_instalment UNIQUE (recharge_id, instalment_no),
    CONSTRAINT fk_emi_recharge FOREIGN KEY (recharge_id) REFERENCES recharge_orders(id),
    CONSTRAINT fk_emi_user FOREIGN KEY (user_id) REFERENCES users(id),
    CONSTRAINT chk_emi_status CHECK (status IN ('PENDING','PAID','OVERDUE','WAIVED'))
);

CREATE INDEX idx_emi_user ON recharge_emi_schedules(user_id, status);
CREATE INDEX idx_emi_due ON recharge_emi_schedules(due_date, status);
