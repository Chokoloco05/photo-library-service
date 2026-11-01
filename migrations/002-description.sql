-- Additive migration: previous application versions remain compatible.
ALTER TABLE photos ADD COLUMN description varchar(1000) NOT NULL DEFAULT '';
