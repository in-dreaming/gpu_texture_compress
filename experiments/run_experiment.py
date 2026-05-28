#!/usr/bin/env python3
"""
Experiment orchestrator for GPU texture compression autoresearch.
DO NOT MODIFY - this is fixed infrastructure.

Usage:
    python experiments/run_experiment.py --config experiments/configs/quick_bc1.json
    python experiments/run_experiment.py --config experiments/configs/full_sweep.json
"""

import argparse
import os
import subprocess
import sys
import time
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.parent
BUILD_DIR = PROJECT_ROOT / "build"
RESULTS_TSV = PROJECT_ROOT / "experiments" / "results.tsv"


def find_runner():
    """Find the gtc_runner executable."""
    candidates = [
        BUILD_DIR / "Release" / "gtc_runner.exe",
        BUILD_DIR / "gtc_runner.exe",
        BUILD_DIR / "Debug" / "gtc_runner.exe",
        BUILD_DIR / "RelWithDebInfo" / "gtc_runner.exe",
    ]
    for c in candidates:
        if c.exists():
            return c
    return None


def build_project():
    """Build the project. Returns (success, error_output)."""
    print("[BUILD] cmake --build build --config Release ...")
    result = subprocess.run(
        ["cmake", "--build", str(BUILD_DIR), "--config", "Release"],
        capture_output=True, text=True, timeout=120,
        cwd=str(PROJECT_ROOT)
    )
    if result.returncode != 0:
        return False, result.stderr[-2000:]
    return True, ""


def run_experiment(runner_exe, config_path, timeout=180):
    """Run gtc_runner with given config. Returns (success, stdout)."""
    print(f"[RUN] {runner_exe} --config {config_path}")
    try:
        result = subprocess.run(
            [str(runner_exe), "--config", str(config_path)],
            capture_output=True, text=True, timeout=timeout,
            cwd=str(PROJECT_ROOT)
        )
        return result.returncode == 0, result.stdout + result.stderr
    except subprocess.TimeoutExpired:
        return False, "TIMEOUT"


def parse_results(output):
    """Parse machine-readable results from runner output."""
    results = {}
    for line in output.splitlines():
        line = line.strip()
        if ":" in line and not line.startswith("=") and not line.startswith("#"):
            key, _, value = line.partition(":")
            key = key.strip()
            value = value.strip()
            try:
                results[key] = float(value)
            except ValueError:
                results[key] = value
    return results


def get_git_commit():
    """Get current short git commit hash."""
    result = subprocess.run(
        ["git", "rev-parse", "--short=7", "HEAD"],
        capture_output=True, text=True, cwd=str(PROJECT_ROOT)
    )
    return result.stdout.strip() if result.returncode == 0 else "unknown"


def log_result(commit, format_name, metrics, status, description):
    """Append result to results.tsv."""
    if not RESULTS_TSV.parent.exists():
        RESULTS_TSV.parent.mkdir(parents=True, exist_ok=True)

    if not RESULTS_TSV.exists():
        with open(RESULTS_TSV, "w") as f:
            f.write("commit\tformat\tavg_psnr\tavg_ssim\tavg_flip\ttime_ms\tstatus\tdescription\n")

    with open(RESULTS_TSV, "a") as f:
        f.write(f"{commit}\t{format_name}\t"
                f"{metrics.get('avg_psnr', 0):.3f}\t"
                f"{metrics.get('avg_ssim', 0):.4f}\t"
                f"{metrics.get('avg_flip', 0):.4f}\t"
                f"{metrics.get('avg_time_ms', 0):.2f}\t"
                f"{status}\t{description}\n")


def main():
    parser = argparse.ArgumentParser(description="GPU Texture Compression Experiment Orchestrator")
    parser.add_argument("--config", required=True, help="Path to experiment config JSON")
    parser.add_argument("--skip-build", action="store_true", help="Skip build step")
    parser.add_argument("--description", default="", help="Experiment description for TSV")
    args = parser.parse_args()

    # 1. Build
    if not args.skip_build:
        ok, err = build_project()
        if not ok:
            print(f"[BUILD FAILED]\n{err}")
            commit = get_git_commit()
            log_result(commit, "ALL", {}, "crash", f"build failure: {args.description}")
            sys.exit(1)
        print("[BUILD] Success")

    # 2. Find runner
    runner = find_runner()
    if not runner:
        print("[ERROR] Cannot find gtc_runner executable. Did the build succeed?")
        sys.exit(1)

    # 3. Run
    t0 = time.time()
    ok, output = run_experiment(runner, args.config)
    elapsed = time.time() - t0

    # 4. Parse and log
    commit = get_git_commit()
    if not ok:
        print(f"[RUN FAILED] ({elapsed:.1f}s)")
        if output == "TIMEOUT":
            print("  Experiment timed out (>180s)")
        else:
            lines = output.splitlines()
            for line in lines[-50:]:
                print(f"  {line}")
        log_result(commit, "ALL", {}, "crash", f"runtime failure: {args.description}")
        sys.exit(1)

    metrics = parse_results(output)
    fmt = metrics.get("format", "UNKNOWN")
    print(f"\n[RESULTS] ({elapsed:.1f}s)")
    print(f"  format:    {fmt}")
    print(f"  avg_psnr:  {metrics.get('avg_psnr', 0):.4f}")
    print(f"  avg_ssim:  {metrics.get('avg_ssim', 0):.4f}")
    print(f"  avg_flip:  {metrics.get('avg_flip', 0):.4f}")
    print(f"  time_ms:   {metrics.get('avg_time_ms', 0):.2f}")

    log_result(commit, fmt, metrics, "pending", args.description)
    print(f"\n[LOGGED] -> {RESULTS_TSV}")


if __name__ == "__main__":
    main()
