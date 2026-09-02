-- Adds service_type to distinguish MOBILE vs DTH recharge orders.
-- Every existing row is a mobile recharge, so the DEFAULT + NOT NULL
-- backfills them all to 'MOBILE' automatically -- no separate UPDATE needed.
ALTER TABLE recharge_orders
    ADD COLUMN service_type VARCHAR(20) NOT NULL DEFAULT 'MOBILE';

CREATE INDEX idx_recharge_orders_service_type ON recharge_orders (service_type);