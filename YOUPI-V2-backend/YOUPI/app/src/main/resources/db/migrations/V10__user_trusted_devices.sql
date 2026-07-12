-- ═══════════════════════════════════════════════════════════
-- V10: User Trusted Devices — device-binding for MPIN-only login
-- YouPI Super App · Nexospendz Finothrive Pvt. Ltd.
-- PostgreSQL compatible
-- ═══════════════════════════════════════════════════════════

-- A device becomes "trusted" for a user the moment it completes a real
-- OTP/Firebase phone verification (see AuthService.verifyOtp /
-- verifyFirebaseToken). From then on, that same device_id can log in via
-- MPIN alone (POST /v1/auth/mpin/verify) without repeating OTP.
--
-- Any device_id NOT in this table for that user is treated as unrecognised
-- -- even with the correct MPIN, AuthService.verifyMpin() will refuse and
-- force an OTP re-verification first (DeviceNotTrustedException). This is
-- what stops "I know the mobile number + MPIN" alone from being enough to
-- log in from an arbitrary device.
CREATE TABLE user_trusted_devices (
    id               UUID NOT NULL DEFAULT gen_random_uuid(),
    user_id          UUID NOT NULL,
    device_id        VARCHAR(128) NOT NULL,
    first_trusted_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_used_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    CONSTRAINT fk_trusted_device_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT uq_user_device UNIQUE (user_id, device_id)
);

CREATE INDEX idx_trusted_devices_user_id ON user_trusted_devices(user_id);