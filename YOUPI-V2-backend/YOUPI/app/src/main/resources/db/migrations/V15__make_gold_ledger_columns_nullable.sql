-- ═══════════════════════════════════════════════════════════
-- V15: gold_reward_ledger & gold_withdraw_requests — grams/rate
-- columns ko nullable banao (current coin-based version mein
-- Augmont rate/grams track nahi hota; columns future integration
-- ke liye rakhe hain, ab optional)
-- ═══════════════════════════════════════════════════════════

ALTER TABLE gold_reward_ledger
    ALTER COLUMN gold_rate_at_credit DROP NOT NULL,
    ALTER COLUMN gold_grams DROP NOT NULL;

ALTER TABLE gold_withdraw_requests
    ALTER COLUMN gold_grams_deducted DROP NOT NULL,
    ALTER COLUMN gold_rate_at_withdraw DROP NOT NULL;