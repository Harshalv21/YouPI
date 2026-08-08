-- V__create_admins_table.kt (rename to next available V-number, e.g. V18__create_admins_table.sql)
-- Run this against your actual DB after confirming the target migration number.

CREATE TABLE IF NOT EXISTS admins (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    name VARCHAR(255) NOT NULL,
    role VARCHAR(50) NOT NULL DEFAULT 'ADMIN',   -- ADMIN, SUPER_ADMIN -- extend later for role-based screens
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_login_at TIMESTAMPTZ
);

-- NOT NEEDED: confirmed UserEntity already has `isActive` (boolean) and
-- `isKycVerified` (boolean) columns -- the admin panel's Block/Unblock
-- action reuses is_active directly, no new column required here.

-- Seed your first admin user manually AFTER this migration runs --
-- generate a bcrypt hash for your chosen password (see the note in
-- AdminAuthService.kt's doc comment for how), then:
--
-- INSERT INTO admins (email, password_hash, name, role)
-- VALUES ('owner@nexospendz.com', '<bcrypt-hash-here>', 'Owner Name', 'SUPER_ADMIN');