CREATE TABLE auth_sessions (
  token_hash text PRIMARY KEY,
  csrf_token text NOT NULL,
  credential_id text NOT NULL,
  expires_at timestamptz NOT NULL
);
CREATE INDEX auth_sessions_expiry ON auth_sessions(expires_at);
CREATE TABLE auth_attempts (
  bucket text PRIMARY KEY,
  attempts integer NOT NULL DEFAULT 1,
  expires_at timestamptz NOT NULL DEFAULT now() + interval '15 minutes'
);
