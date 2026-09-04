-- Gold SIP / goal-based investing. See Gold SIP Feature Spec (Sec 4.1)
-- and its handoff doc for the original proposed shape -- this adds one
-- extra column (missed_debit_attempts) beyond that proposal, to support
-- the retry-then-pause failure handling decided in this session (open
-- decision 6.1 in the spec).

CREATE TABLE gold_goals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),
    title VARCHAR(100) NOT NULL,
    category VARCHAR(50),
    category_emoji VARCHAR(8),
    target_amount NUMERIC(12,2) NOT NULL,
    saved_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
    frequency VARCHAR(10) NOT NULL, -- DAILY / WEEKLY / MONTHLY
    installment_amount NUMERIC(10,2) NOT NULL,
    next_deduction_date DATE NOT NULL,
    auto_debit_active BOOLEAN NOT NULL DEFAULT true,
    -- Consecutive failed auto-debit attempts (insufficient wallet balance).
    -- Reset to 0 on any successful debit. At 3, auto_debit_active is
    -- flipped false by the scheduler and the user must resume manually.
    missed_debit_attempts SMALLINT NOT NULL DEFAULT 0,
    completed BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deadline DATE NOT NULL
);

CREATE INDEX idx_gold_goals_user_id ON gold_goals(user_id);

-- Scheduler's daily due-goals query filters on exactly these three
-- columns -- partial index keeps that query cheap as the table grows.
CREATE INDEX idx_gold_goals_due ON gold_goals(next_deduction_date)
    WHERE auto_debit_active = true AND completed = false;

CREATE TABLE gold_goal_contributions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    goal_id UUID NOT NULL REFERENCES gold_goals(id) ON DELETE CASCADE,
    gold_txn_id UUID REFERENCES gold_transactions(id), -- links back to the
                                                         -- actual Augmont buy
    type VARCHAR(20) NOT NULL, -- AUTO_DEBIT / MANUAL_TOPUP
    grams NUMERIC(12,6) NOT NULL,
    price_per_gram NUMERIC(10,2) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_gold_goal_contributions_goal_id ON gold_goal_contributions(goal_id);