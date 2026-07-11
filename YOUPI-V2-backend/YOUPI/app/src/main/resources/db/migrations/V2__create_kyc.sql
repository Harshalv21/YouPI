-- ═══════════════════════════════════════════════════════════
-- V2: KYC Records + Smart Saver Documents (PostgreSQL)
-- ═══════════════════════════════════════════════════════════

CREATE TABLE kyc_records (
    id                  UUID NOT NULL DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL,
    aadhaar_encrypted   BYTEA,
    aadhaar_last4       VARCHAR(4),
    aadhaar_verified    BOOLEAN NOT NULL DEFAULT false,
    aadhaar_verified_at TIMESTAMP NULL,
    pan_number          VARCHAR(10),
    pan_verified        BOOLEAN NOT NULL DEFAULT false,
    pan_verified_at     TIMESTAMP NULL,
    selfie_gcs_path     VARCHAR(500),
    pan_front_gcs       VARCHAR(500),
    pan_back_gcs        VARCHAR(500),
    aadhaar_front_gcs   VARCHAR(500),
    aadhaar_back_gcs    VARCHAR(500),
    face_match_score    DECIMAL(5,2),
    kyc_status          VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    rejection_reason    TEXT,
    verified_at         TIMESTAMP NULL,
    digio_request_id    VARCHAR(100),
    karza_request_id    VARCHAR(100),
    created_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    CONSTRAINT uq_kyc_user UNIQUE (user_id),
    CONSTRAINT fk_kyc_user FOREIGN KEY (user_id) REFERENCES users(id),
    CONSTRAINT chk_kyc_status CHECK (kyc_status IN
        ('PENDING','AADHAAR_DONE','PAN_DONE','SELFIE_DONE','VERIFIED','REJECTED'))
);

CREATE INDEX idx_kyc_user ON kyc_records(user_id);
CREATE INDEX idx_kyc_status ON kyc_records(kyc_status);

CREATE TABLE smart_saver_documents (
    id               UUID NOT NULL DEFAULT gen_random_uuid(),
    user_id          UUID NOT NULL,
    doc_type         VARCHAR(50) NOT NULL,
    gcs_path         VARCHAR(500) NOT NULL,
    status           VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    rejection_reason TEXT,
    reviewed_by      UUID,
    reviewed_at      TIMESTAMP NULL,
    created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    CONSTRAINT fk_ss_doc_user FOREIGN KEY (user_id) REFERENCES users(id),
    CONSTRAINT fk_ss_doc_reviewer FOREIGN KEY (reviewed_by) REFERENCES users(id),
    CONSTRAINT chk_ss_doc_type CHECK (doc_type IN
        ('INCOME_PROOF','BANK_STATEMENT','EMPLOYMENT_LETTER','ITR','SALARY_SLIP','BUSINESS_PROOF')),
    CONSTRAINT chk_ss_doc_status CHECK (status IN ('PENDING','APPROVED','REJECTED'))
);

CREATE INDEX idx_ss_docs_user ON smart_saver_documents(user_id, status);