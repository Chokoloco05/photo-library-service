\set ON_ERROR_STOP on
\getenv shard_password POSTGRES_PASSWORD
BEGIN;
SELECT pg_advisory_xact_lock(726042);
CREATE EXTENSION IF NOT EXISTS postgres_fdw;
CREATE SERVER IF NOT EXISTS photo_shard_1 FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (host 'photo-db-shard-1', port '5432', dbname 'photo_service', connect_timeout '5');
SELECT format('CREATE USER MAPPING IF NOT EXISTS FOR photo SERVER photo_shard_1 OPTIONS (user %L, password %L)', 'photo', :'shard_password') \gexec

DO $$ BEGIN
    IF (SELECT relkind FROM pg_class WHERE oid='public.photos'::regclass) = 'r' THEN
        LOCK TABLE public.photos IN ACCESS EXCLUSIVE MODE;
        CREATE SCHEMA sharding_archive;
        ALTER TABLE public.photos SET SCHEMA sharding_archive;
        CREATE TABLE public.photos (LIKE sharding_archive.photos INCLUDING DEFAULTS INCLUDING CONSTRAINTS)
            PARTITION BY HASH(id);
        CREATE TABLE public.photos_shard_0 PARTITION OF public.photos FOR VALUES WITH (MODULUS 2, REMAINDER 0);
        ALTER TABLE public.photos_shard_0 ADD PRIMARY KEY(id);
        CREATE INDEX ON public.photos_shard_0(sha256);
        CREATE INDEX ON public.photos_shard_0(created_at DESC,id);
        CREATE FOREIGN TABLE public.photos_shard_1 PARTITION OF public.photos FOR VALUES WITH (MODULUS 2, REMAINDER 1)
            SERVER photo_shard_1 OPTIONS (schema_name 'public', table_name 'photos');

        -- Retrying after an uncertain remote commit preserves matching copied rows.
        INSERT INTO public.photos_shard_1
            SELECT source.* FROM sharding_archive.photos source
            WHERE satisfies_hash_partition('public.photos'::regclass,2,1,source.id)
            AND NOT EXISTS (SELECT FROM public.photos_shard_1 target WHERE target.id=source.id);
        INSERT INTO public.photos_shard_0
            SELECT * FROM sharding_archive.photos
            WHERE satisfies_hash_partition('public.photos'::regclass,2,0,id);
        IF EXISTS (TABLE sharding_archive.photos EXCEPT TABLE public.photos)
            OR EXISTS (TABLE public.photos EXCEPT TABLE sharding_archive.photos) THEN
            RAISE EXCEPTION 'Sharding copy differs from the original library';
        END IF;
    END IF;
    IF to_regclass('public.library_revision') IS NOT NULL
        AND NOT EXISTS (SELECT FROM pg_trigger WHERE tgrelid='public.photos'::regclass AND tgname='library_revision_changed') THEN
        CREATE TRIGGER library_revision_changed AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE ON public.photos
            FOR EACH STATEMENT EXECUTE FUNCTION public.bump_library_revision();
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.photo_sharding (
    singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
    shard_host text NOT NULL,
    shard_database text NOT NULL,
    installed_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public.photo_sharding(singleton,shard_host,shard_database)
    VALUES(true,'photo-db-shard-1','photo_service') ON CONFLICT DO NOTHING;
COMMIT;
