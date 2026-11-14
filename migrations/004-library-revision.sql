CREATE TABLE library_revision (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  token uuid NOT NULL DEFAULT gen_random_uuid()
);
INSERT INTO library_revision(singleton) VALUES(true);

CREATE FUNCTION bump_library_revision() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE format('UPDATE %I.library_revision SET token=gen_random_uuid() WHERE singleton', TG_TABLE_SCHEMA);
  RETURN NULL;
END;
$$;

CREATE TRIGGER library_revision_changed
AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE ON photos
FOR EACH STATEMENT EXECUTE FUNCTION bump_library_revision();
