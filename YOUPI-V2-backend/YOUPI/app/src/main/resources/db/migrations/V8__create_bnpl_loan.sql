-- ═══════════════════════════════════════════════════════════
-- V8: BNPL + Loan Applications, Accounts, EMI Schedules (PostgreSQL)
-- ═══════════════════════════════════════════════════════════

-- ── BNPL Applications ──
CREATE TABLE bnpl_applications (
    id               UUID NOT NULL DEFAULT gen_random_uuid(),
    user_id          UUID NOT NULL,
    employment_type  VARCHAR(30),
    monthly_income   DECIMAL(12,2),
    cibil_score      SMALLINT,
    cibil_report_id  VARCHAR(100),
    cibil_consent    BOOLEAN NOT NULL DEFAULT false,
    tc_consent       BOOLEAN NOT NULL DEFAULT false,
    approved_limit   DECIMAL(10,2),
    status           VARCHAR(30) NOT NULL DEFAULT 'SUBMITTED',
    rejection_reason TEXT,
    reviewed_by      UUID,
    reviewed_at      TIMESTAMP NULL,
    created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    CONSTRAINT fk_bnpl_app_user FOREIGN KEY (user_id) REFERENCES users(id),
    CONSTRAINT fk_bnpl_reviewer FOREIGN KEY (reviewed_by) REFERENCES users(id),
    CONSTRAINT chk_bnpl_employment CHECK (employment_type IN ('STUDENT','SALARIED','SELF_EMPLOYED')),
    CONSTRAINT chk_bnpl_status CHECK (status IN ('SUBMITTED','UNDER_REVIEW','APPROVED','REJECTED'))
);

CREATE INDEX idx_bnpl_app_user ON bnpl_applications(user_id, created_at);
CREATE INDEX idx_bnpl_app_status ON bnpl_applications(status);

-- ── BNPL Accounts ──
CREATE TABLE bnpl_accounts (
    id              UUID NOT NULL DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL,
    application_id  UUID NOT NULL,
    total_limit     DECIMAL(10,2) NOT NULL,
    used_limit      DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    available_limit DECIMAL(10,2) GENERATED ALWAYS AS (total_limit - used_limit) STORED,
    status          VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    CONSTRAINT uq_bnpl_user UNIQUE (user_id),
    CONSTRAINT fk_bnpl_acct_user FOREIGN KEY (user_id) REFERENCES users(id),
    CONSTRAINT fk_bnpl_acct_app FOREIGN KEY (application_id) REFERENCES bnpl_applications(id),
    CONSTRAINT chk_bnpl_limit CHECK (total_limit > 0),
    CONSTRAINT chk_bnpl_used CHECK (used_limit >= 0),
    CONSTRAINT chk_bnpl_acct_status CHECK (status IN ('ACTIVE','SUSPENDED','CLOSED'))
);

-- ── Loan Applications ──
CREATE TABLE loan_applications (
    id               UUID NOT NULL DEFAULT gen_random_uuid(),
    user_id          UUID NOT NULL,
    full_name        VARCHAR(100) NOT NULL,
    date_of_birth    DATE NOT NULL,
    pan_number       VARCHAR(10) NOT NULL,
    pan_gcs_path     VARCHAR(500),
    fathers_name     VARCHAR(100),
    address          TEXT,
    pincode          VARCHAR(6),
    city             VARCHAR(50),
    state            VARCHAR(50),
    aadhaar_last4    VARCHAR(4),
    aadhaar_front_gcs VARCHAR(500),
    aadhaar_back_gcs  VARCHAR(500),
    employment_type  VARCHAR(30),
    employer_name    VARCHAR(100),
    work_email       VARCHAR(150),
    monthly_income   DECIMAL(12,2),
    annual_turnover  DECIMAL(15,2),
    years_experience VARCHAR(10),
    cibil_score      SMALLINT,
    cibil_consent    BOOLEAN NOT NULL DEFAULT false,
    requested_amount DECIMAL(12,2),
    approved_amount  DECIMAL(12,2),
    interest_rate    DECIMAL(5,2),
    tenure_months    SMALLINT,
    status           VARCHAR(30) NOT NULL DEFAULT 'SUBMITTED',
    rejection_reason TEXT,
    reviewed_by      UUID,
    reviewed_at      TIMESTAMP NULL,
    created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    CONSTRAINT fk_loan_app_user FOREIGN KEY (user_id) REFERENCES users(id),
    CONSTRAINT fk_loan_reviewer FOREIGN KEY (reviewed_by) REFERENCES users(id),
    CONSTRAINT chk_loan_employment CHECK (employment_type IN ('STUDENT','SALARIED','SELF_EMPLOYED')),
    CONSTRAINT chk_loan_status CHECK (status IN
        ('SUBMITTED','UNDER_REVIEW','APPROVED','REJECTED','DISBURSED','CLOSED'))
);

CREATE INDEX idx_loan_app_user ON loan_applications(user_id, created_at);
CREATE INDEX idx_loan_app_status ON loan_applications(status);

-- ── Loan Accounts ──
CREATE TABLE loan_accounts (
    id                  UUID NOT NULL DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL,
    application_id      UUID NOT NULL,
    principal           DECIMAL(12,2) NOT NULL,
    interest_rate       DECIMAL(5,2) NOT NULL,
    tenure_months       SMALLINT NOT NULL,
    monthly_emi         DECIMAL(10,2) NOT NULL,
    outstanding_balance DECIMAL(12,2) NOT NULL,
    bank_partner        VARCHAR(50) NOT NULL DEFAULT 'AXIS_BANK',
    bank_loan_ref       VARCHAR(100),
    enach_status        VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    enach_mandate_id    VARCHAR(100),
    disbursed_at        TIMESTAMP NULL,
    status              VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    created_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    CONSTRAINT uq_loan_user UNIQUE (user_id),
    CONSTRAINT fk_loan_acct_user FOREIGN KEY (user_id) REFERENCES users(id),
    CONSTRAINT fk_loan_acct_app FOREIGN KEY (application_id) REFERENCES loan_applications(id),
    CONSTRAINT chk_enach_status CHECK (enach_status IN ('PENDING','ACTIVE','FAILED','CANCELLED')),
    CONSTRAINT chk_loan_acct_status CHECK (status IN ('ACTIVE','CLOSED','NPA'))
);

-- ── Loan EMI Schedule ──
CREATE TABLE loan_emi_schedule (
    id             UUID NOT NULL DEFAULT gen_random_uuid(),
    loan_id        UUID NOT NULL,
    emi_number     SMALLINT NOT NULL,
    due_date       DATE NOT NULL,
    principal_part DECIMAL(10,2) NOT NULL,
    interest_part  DECIMAL(10,2) NOT NULL,
    total_emi      DECIMAL(10,2) NOT NULL,
    status         VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    paid_at        TIMESTAMP NULL,
    payment_ref    VARCHAR(100),
    created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    CONSTRAINT uq_loan_emi UNIQUE (loan_id, emi_number),
    CONSTRAINT fk_loan_emi_account FOREIGN KEY (loan_id) REFERENCES loan_accounts(id),
    CONSTRAINT chk_loan_emi_status CHECK (status IN ('PENDING','PAID','OVERDUE','WAIVED'))
);

CREATE INDEX idx_loan_emi_due ON loan_emi_schedule(due_date, status);