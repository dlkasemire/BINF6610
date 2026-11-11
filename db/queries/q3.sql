-- q3: How many variants, and how many PASS, in each run?
SELECT r.run_id,
       COUNT(v.run_id) AS n_variants,
       COALESCE(SUM(v.filter = 'PASS'), 0) AS n_pass
FROM runs r
LEFT JOIN variants v ON v.run_id = r.run_id
GROUP BY r.run_id;
