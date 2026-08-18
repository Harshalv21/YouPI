CREATE TABLE onboarding_answers (
    id            UUID PRIMARY KEY,
    user_id       UUID NOT NULL REFERENCES users(id),
    question_id   VARCHAR(64) NOT NULL,
    option_ids    TEXT NOT NULL,          -- comma-separated option ids
    other_text    VARCHAR(200),           -- free text when "Other" picked
    answered_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, question_id)         -- re-answer overwrites, no duplicates
);

CREATE INDEX idx_onboarding_answers_user ON onboarding_answers(user_id);