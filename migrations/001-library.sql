CREATE TABLE photos (
  id uuid PRIMARY KEY,
  filename varchar(200) NOT NULL,
  title varchar(200) NOT NULL,
  mime_type text NOT NULL CHECK (mime_type IN ('image/jpeg', 'image/png', 'image/webp')),
  size_bytes integer NOT NULL CHECK (size_bytes > 0 AND size_bytes <= 10485760),
  width integer NOT NULL CHECK (width > 0),
  height integer NOT NULL CHECK (height > 0),
  sha256 char(64) NOT NULL,
  visual_hash char(16) NOT NULL,
  original bytea NOT NULL,
  thumbnail bytea NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX photos_sha256_idx ON photos (sha256);
CREATE INDEX photos_created_at_idx ON photos (created_at DESC, id);
