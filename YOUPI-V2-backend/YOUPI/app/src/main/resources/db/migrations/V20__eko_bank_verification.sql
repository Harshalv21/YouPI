-- ═══════════════════════════════════════════════════════════
-- V20: Eko integration — adds bank account verification fields
-- (net-new step, no prior vendor existed for this) and eko_request_id
-- for PAN verification (replaces Karza, which was never actually wired
-- up beyond a TODO stub — see UserService.kt history).
--
-- karza_request_id and digio_request_id columns are NOT dropped: no
-- historical data exists to preserve since both were stub values, but
-- dropping columns is unnecessary churn for a column nobody will write
-- to anymore. New code should stop writing to karza_request_id and use
-- eko_pan_request_id instead.
-- ═══════════════════════════════════════════════════════════

ALTER TABLE kyc_records
    ADD COLUMN eko_pan_request_id       VARCHAR(100),
    ADD COLUMN pan_holder_name          VARCHAR(200),
    ADD COLUMN bank_account_last4       VARCHAR(4),
    ADD COLUMN bank_ifsc                VARCHAR(11),
    ADD COLUMN bank_account_holder_name VARCHAR(200),
    ADD COLUMN bank_name                VARCHAR(200),
    ADD COLUMN bank_branch              VARCHAR(200),
    ADD COLUMN bank_verified            BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN bank_verified_at         TIMESTAMP NULL,
    ADD COLUMN eko_bank_request_id      VARCHAR(100);

-- Bank verification is an additional KYC step, not a replacement for any
-- existing one -- kyc_status enum unchanged, bank_verified is tracked as
-- its own flag (mirrors how aadhaar_verified/pan_verified already work)
-- rather than folded into the PENDING -> ... -> VERIFIED state machine,
-- since product hasn't specified where in that sequence it belongs yet.