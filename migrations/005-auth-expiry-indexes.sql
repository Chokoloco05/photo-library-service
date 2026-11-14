-- Additive migration, compatible with application Pods running the previous version.
-- Login and session creation remove expired rows using these predicates.
CREATE INDEX auth_sessions_expires_at_idx ON auth_sessions (expires_at);
CREATE INDEX auth_attempts_expires_at_idx ON auth_attempts (expires_at);
