SELECT
  users.id,
  users.name
FROM users
WHERE users.active = true
ORDER BY users.created_at DESC;
