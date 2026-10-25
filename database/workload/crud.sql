INSERT INTO public.backend_workload_items (payload)
VALUES ('pgbench-' || clock_timestamp()::text)
RETURNING id \gset

SELECT id, payload, version
FROM public.backend_workload_items
WHERE id = :id;

UPDATE public.backend_workload_items
SET payload = 'updated-' || clock_timestamp()::text,
    version = version + 1,
    updated_at = clock_timestamp()
WHERE id = :id;

DELETE FROM public.backend_workload_items
WHERE id = :id;
