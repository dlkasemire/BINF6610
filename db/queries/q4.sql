-- q4: Every sample, its sex, and how many runs used it.
SELECT s.sample_id,
       s.sex,
       COUNT(rs.run_id) AS n_runs
FROM samples s
LEFT JOIN run_samples rs ON rs.sample_id = s.sample_id
GROUP BY s.sample_id
ORDER BY s.sample_id;
