ALTER TABLE recharge_orders ADD COLUMN wallet_amount NUMERIC(10,2);
ALTER TABLE recharge_orders ADD COLUMN gateway_amount NUMERIC(10,2);