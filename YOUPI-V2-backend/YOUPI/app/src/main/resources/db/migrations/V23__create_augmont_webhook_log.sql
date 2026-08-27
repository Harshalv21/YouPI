-- Audit log for every inbound Augmont webhook event, regardless of type.
-- KYC/Buy/Sell events additionally update the matching local record
-- directly (see AugmontWebhookService.handle()) -- this table is the
-- safety net so nothing is silently dropped, including event types
-- (withdraw/order/gateway-transactions/user_create/redeem) we don't yet
-- have a local feature/table to apply against.
CREATE TABLE augmont_webhook_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type VARCHAR(32) NOT NULL,
    status VARCHAR(32),
    unique_id VARCHAR(64),
    transaction_id VARCHAR(64),
    merchant_transaction_id VARCHAR(64),
    matched_local_record BOOLEAN NOT NULL DEFAULT FALSE,
    raw_payload TEXT NOT NULL,
    received_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_augmont_webhook_events_type ON augmont_webhook_events(event_type);
CREATE INDEX idx_augmont_webhook_events_txn ON augmont_webhook_events(transaction_id);
CREATE INDEX idx_augmont_webhook_events_unique_id ON augmont_webhook_events(unique_id);