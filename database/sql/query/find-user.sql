-- Tim user theo email hoac username (khong tra password_hash).
-- Sua gia tri term trong CTE thanh email/username can tim.
-- Vi du: 'minh.nguyen42@example.com' hoac 'minh.nguyen42'.

WITH search_input AS (
  SELECT 'user@example.com'::text AS term
)
SELECT u.id,
       u.username,
       u.email,
       u.full_name,
       u.phone,
       u.status,
       u.is_email_verified,
       u.created_at,
       u.last_login_at
FROM users AS u
CROSS JOIN search_input AS s
WHERE lower(u.email) = lower(s.term)
   OR u.username = s.term;

-- EXPLAIN mode: chay rieng query nay de xem execution plan va thoi gian thuc thi.
-- ANALYZE thuc su chay SELECT; query chi doc du lieu.
-- Sua term o day giong gia tri o query phia tren.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
WITH search_input AS (
  SELECT 'user@example.com'::text AS term
)
SELECT u.id,
       u.username,
       u.email,
       u.full_name,
       u.phone,
       u.status,
       u.is_email_verified,
       u.created_at,
       u.last_login_at
FROM users AS u
CROSS JOIN search_input AS s
WHERE lower(u.email) = lower(s.term)
   OR u.username = s.term;

-- Tim gan dung theo ten/email/so dien thoai (khong phan biet hoa thuong).
-- Tim contains voi '%...%' nen thuong Seq Scan: phone va full_name khong co index,
-- va index email(lower) khong phuc vu cho ILIKE voi wildcard dau chuoi.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
WITH search_input AS (
  SELECT 'Jonathan.jones54@hotmail.com'::text AS term
)
SELECT u.id,
       u.username,
       u.email,
       u.full_name,
       u.phone,
       u.status
FROM users AS u
CROSS JOIN search_input AS s
WHERE s.term <> ''
  AND (u.username ILIKE '%' || s.term || '%'
       OR u.email ILIKE '%' || s.term || '%'
       OR u.full_name ILIKE '%' || s.term || '%'
       OR u.phone ILIKE '%' || s.term || '%')
ORDER BY u.id DESC
LIMIT 50;