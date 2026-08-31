-- Stores Augmont's own invoice number (e.g. "GPRA082205", seen in their
-- Buy webhook sample) when they send one, so it can appear on our
-- generated invoice PDF alongside our own transaction id. Nullable --
-- falls back to our own transaction id if Augmont doesn't return one.
ALTER TABLE gold_transactions ADD COLUMN augmont_invoice_number VARCHAR(64);
