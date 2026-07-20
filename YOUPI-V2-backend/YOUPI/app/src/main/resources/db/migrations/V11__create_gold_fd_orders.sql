CREATE TABLE gold_fd_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    augmont_fd_id VARCHAR(255) NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_gold_fd_orders_user_id ON gold_fd_orders(user_id);
CREATE INDEX idx_gold_fd_orders_augmont_fd_id ON gold_fd_orders(augmont_fd_id);