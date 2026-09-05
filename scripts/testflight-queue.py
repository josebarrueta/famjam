"""Durable FIFO: main's first-parent history is the queue, deployments its ledger.

GitHub concurrency is only a mutex. Lost/coalesced wakeups are safe because every
wake scans history from the immutable bootstrap SHA. A scheduled wake recovers
missed events. Only a verified upload gets a success ledger entry.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request

ENVIRONMENT = 'rallyroo-testflight'
REPOSITORY = 'josebarrueta/rallyroo'


def next_commit(commits, completed):
    return next((sha for sha in commits if sha not in completed), None)


def next_build(deployments):
    build = max([100] + [int(d['payload']['build']) for d in deployments]) + 1
    if build > 9999:
        raise RuntimeError('Build number range exhausted; migrate numbering policy')
    return build


def api(path, payload=None):
    request = urllib.request.Request(
        f'https://api.github.com/repos/{REPOSITORY}/{path}',
        data=json.dumps(payload).encode() if payload is not None else None,
        headers={'Authorization': 'Bearer ' + os.environ['GH_TOKEN'],
                 'Accept': 'application/vnd.github+json', 'Content-Type': 'application/json',
                 'X-GitHub-Api-Version': '2022-11-28'})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def pages(path, key=None):
    results = []
    for page in range(1, 1001):
        data = api(path + ('&' if '?' in path else '?') + f'per_page=100&page={page}')
        batch = data[key] if key else data
        results.extend(batch)
        if len(batch) < 100:
            return results
    raise RuntimeError('Pagination limit reached; refusing incomplete queue history')


def git(*args):
    return subprocess.check_output(['git', *args], stderr=subprocess.DEVNULL).decode().strip()


def candidate():
    seed = os.environ.get('TESTFLIGHT_START_SHA', '')
    if len(seed) != 40 or any(c not in '0123456789abcdef' for c in seed):
        raise RuntimeError('Set TESTFLIGHT_START_SHA to the immutable bootstrap main commit')
    history = git('rev-list', '--first-parent', 'origin/main').splitlines()
    if seed not in history:
        raise RuntimeError('Bootstrap commit is not on main first-parent history')
    history = list(reversed(history[:history.index(seed) + 1]))
    relevant = []
    for sha in history:
        files = git('diff-tree', '--no-commit-id', '--name-only', '-r', sha + '^', sha).splitlines()
        if sha == seed or any(f.startswith('clients/ios/') for f in files):
            relevant.append(sha)
    deployments = pages('deployments?environment=' + ENVIRONMENT)
    completed = set()
    for deployment in deployments:
        if deployment.get('payload', {}).get('queue') != 1:
            raise RuntimeError('Unexpected deployment in TestFlight ledger')
        statuses = api(f"deployments/{deployment['id']}/statuses?per_page=1")
        if statuses and statuses[0]['state'] == 'success':
            completed.add(deployment['sha'])
    sha = next_commit(relevant, completed)
    if sha:
        runs = pages(f'actions/workflows/ios.yml/runs?head_sha={sha}&event=push', 'workflow_runs')
        if not any(r['head_sha'] == sha and r['head_branch'] == 'main' and
                   r['conclusion'] == 'success' and r['status'] == 'completed' for r in runs):
            print(f'Queue waiting for successful main iOS CI: {sha}', flush=True)
            return None, deployments
    return sha, deployments


def main():
    sha, deployments = candidate()
    if sys.argv[1:] == ['--plan']:
        with open(os.environ['GITHUB_OUTPUT'], 'a') as f:
            f.write(f'sha={sha or ""}\n')
        return
    if not sha:
        print('No eligible queue item')
        return
    if sha != os.environ['QUEUED_SHA']:
        raise RuntimeError('Queue changed after planning; refusing out-of-order upload')
    build = next_build(deployments)
    deployment = api('deployments', {
        'ref': sha, 'environment': ENVIRONMENT, 'auto_merge': False,
        'required_contexts': [], 'production_environment': False,
        'description': f'Internal TestFlight build {build}',
        'payload': {'queue': 1, 'build': build}})
    status_path = f"deployments/{deployment['id']}/statuses"
    def status(state):
        api(status_path, {'state': state, 'auto_inactive': False,
            'log_url': f"https://github.com/{REPOSITORY}/actions/runs/{os.environ['GITHUB_RUN_ID']}"})
    status('in_progress')
    script = Path(__file__).with_name('upload-testflight.py').resolve()
    try:
        with tempfile.TemporaryDirectory(dir=os.environ['RUNNER_TEMP']) as directory:
            checkout = Path(directory) / 'source'
            git('worktree', 'add', '--detach', str(checkout), sha)
            try:
                subprocess.run([sys.executable, str(script)], cwd=checkout, check=True,
                    env={**os.environ, 'TESTFLIGHT_BUILD_NUMBER': str(build)})
            finally:
                git('worktree', 'remove', '--force', str(checkout))
        status('success')
        print(f'Queue completed {sha}, build {build}', flush=True)
    except BaseException:
        status('failure')
        raise


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(str(error) if isinstance(error, RuntimeError) else 'Queue operation failed; no provider response logged')
        raise SystemExit(1)
