# RESOURCES.md — per-sample job (stages 0–5)

## What I measured

All runs are task 1 (NA12878) of `01_persample.sbatch` on the `courses` partition,
changing one setting at a time.

| run | job | --cpus-per-task | --mem | Elapsed | MaxRSS | core-minutes |
|---|---|---|---|---|---|---|
| baseline | 10741533_1 | 8 | 16G | 00:10:29 | 7101176K (7.1 GB) | 83.9 |
| A | 10743617_1 | 4 | 16G | 00:08:31 | 6871608K (6.9 GB) | 34.1 |
| B | 10743623_1 | 2 | 16G | 00:13:20 | 7472652K (7.5 GB) | 26.7 |
| C | 10743626_1 | 8 | 8G  | 00:07:38 | 7099196K (7.1 GB) | 61.1 |

seff for the baseline run:

    Job ID: 10741534
    Array Job ID: 10741533_1
    State: COMPLETED (exit code 0)
    Cores per node: 8
    CPU Utilized: 00:19:25
    CPU Efficiency: 23.15% of 01:23:52 core-walltime
    Job Wall-clock time: 00:10:29
    Memory Utilized: 6.77 GB
    Memory Efficiency: 42.33% of 16.00 GB

CPU Utilized divided by wall-clock time is 19:25 / 10:29, about 1.9 of the
8 cores busy. The log shows why: stage 5 (HaplotypeCaller) takes about 4 min 40 s
of the run and uses little more than one core; only alignment uses all of them.

The job's `memory.peak` reported 15.3 GB, while MaxRSS and seff said about 7 GB.
I read the 15.3 GB as file cache filling the 16 GB allowance (the BWA index and
the FASTQs being read), not memory the pipeline needed: run C finished
successfully with only 8 GB.

The two 8-core runs took 10:29 and 7:38, so a minute or two between runs is
noise (different nodes, conda activation time); the 2-core run is clearly slower.

## What I set, and why

| | asked first | set to | why |
|---|---|---|---|
| --cpus-per-task | 8 | 4 | 4 cores was as fast as 8 (8:31 vs 7:38–10:29) for under half the core-minutes; 2 cores was ~50 % slower |
| --mem | 16G | 12G | 6.9–7.5 GB used in every run; 8G worked but left only ~1 GB of headroom, and other samples may need more |
| --time | 1:00:00 | 0:30:00 | the slowest run took 13:20; 30 min is over twice that |
