-- ═══════════════════════════════════════════════════════════
-- V1: Users, Authentication, OTP Sessions, Refresh Tokens, MPIN
-- YouPI Super App · Nexospendz Finothrive Pvt. Ltd.
-- PostgreSQL compatible
-- ═══════════════════════════════════════════════════════════

-- ── Users ──
CREATE TABLE users (
    id              CHAR(36) NOT NULL DEFAULT gen_random_uuid()::text,
    mobile          VARCHAR(13) NOT NULL,
    full_name       VARCHAR(100),
    email           VARCHAR(150),
    date_of_birth   DATE,
    firebase_uid    VARCHAR(128),
    is_active       BOOLEAN NOT NULL DEFAULT true,
    is_kyc_verified BOOLEAN NOT NULL DEFAULT false,
    user_type       VARCHAR(20) NOT NULL DEFAULT 'NORMAL',
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    CONSTRAINT uq_users_mobile UNIQUE (mobile),
    CONSTRAINT uq_users_firebase UNIQUE (firebase_uid),
    CONSTRAINT chk_user_type CHECK (user_type IN ('NORMAL','SMART_SAVER','ADMIN'))
);

CREATE INDEX idx_users_mobile ON users(mobile);
CREATE INDEX idx_users_firebase ON users(firebase_uid);

-- ── OTP Sessions (audit trail) ──
CREATE TABLE otp_sessions (
    id           CHAR(36) NOT NULL DEFAULT gen_random_uuid()::text,
    mobile       VARCHAR(13) NOT NULL,
    otp_hash     VARCHAR(64) NOT NULL,
    purpose      VARCHAR(40) NOT NULL,
    attempts     SMALLINT NOT NULL DEFAULT 0,
    max_attempts SMALLINT NOT NULL DEFAULT 3,
    expires_at   TIMESTAMP NOT NULL,
    verified     BOOLEAN NOT NULL DEFAULT false,
    created_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    CONSTRAINT chk_otp_purpose CHECK (purpose IN ('LOGIN','KYC_AADHAAR','DEPOSIT_VERIFY','LOAN_CONSENT'))
);

CREATE INDEX idx_otp_mobile_purpose ON otp_sessions(mobile, purpose, created_at);

-- ── Refresh Tokens ──
CREATE TABLE refresh_tokens (
    id          CHAR(36) NOT NULL DEFAULT gen_random_uuid()::text,
    user_id     CHAR(36) NOT NULL,
    token_hash  VARCHAR(64) NOT NULL,
    device_id   VARCHAR(100),
    device_name VARCHAR(100),
    expires_at  TIMESTAMP NOT NULL,
    revoked     BOOLEAN NOT NULL DEFAULT false,
    revoked_at  TIMESTAMP NULL,
    created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    CONSTRAINT fk_refresh_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX idx_refresh_user ON refresh_tokens(user_id, revoked, expires_at);
CREATE INDEX idx_refresh_token_hash ON refresh_tokens(token_hash);

-- ── User MPIN ──
CREATE TABLE user_mpin (
    user_id      CHAR(36) NOT NULL,
    mpin_hash    VARCHAR(64) NOT NULL,
    attempts     SMALLINT NOT NULL DEFAULT 0,
    locked_until TIMESTAMP NULL,
    updated_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id),
    CONSTRAINT fk_mpin_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
