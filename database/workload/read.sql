SELECT id, payload, version, updated_at
FROM public.backend_workload_items
ORDER BY id DESC
LIMIT 50;
