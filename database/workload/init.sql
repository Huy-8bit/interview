CREATE TABLE IF NOT EXISTS public.backend_workload_items (
    id bigserial PRIMARY KEY,
    payload text NOT NULL,
    version bigint NOT NULL DEFAULT 1,
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

INSERT INTO public.backend_workload_items (payload)
SELECT 'seed-' || n
FROM generate_series(1, 100) AS n
WHERE NOT EXISTS (SELECT 1 FROM public.backend_workload_items);
