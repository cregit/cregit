#!/usr/bin/env python3

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

import argparse
import os
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_BLAME_COMMAND = os.path.join(SCRIPT_DIR, 'formatBlame.pl')
DEFAULT_JOBS = max(1, int((os.cpu_count() or 1) * 0.8))


def get_tracked_files(repo_dir):
    result = subprocess.run(
        ['git', '-C', repo_dir, 'ls-files'],
        capture_output=True, text=True, check=True
    )
    return result.stdout.splitlines()


def process_file(blame_command, blame_extension, revision, repo_dir, name, output_dir, verbose):
    cmd = [blame_command, f'--blameExtension={blame_extension}', f'--revision={revision}', repo_dir, name, output_dir]
    if verbose:
        print(' '.join(cmd), file=sys.stderr)
    return subprocess.run(cmd).returncode


def is_already_done(name, output_dir, blame_extension, overwrite):
    output_file = os.path.join(output_dir, name + blame_extension)
    return not overwrite and os.path.isfile(output_file)


def collect_files(all_files, pattern, repo_dir, output_dir, blame_extension, overwrite, verbose):
    to_process = []
    already_done = 0
    for name in all_files:
        if pattern and not pattern.search(name):
            continue
        if verbose:
            print(f'matched file: [{name}]', file=sys.stderr)
        if is_already_done(name, output_dir, blame_extension, overwrite):
            already_done += 1
            continue
        to_process.append(name)
    return to_process, already_done


def run_parallel(to_process, blame_command, blame_extension, revision, repo_dir, output_dir, verbose, jobs):
    error_count = 0
    completed = 0
    with ThreadPoolExecutor(max_workers=jobs) as executor:
        futures = {
            executor.submit(process_file, blame_command, blame_extension,
                            revision, repo_dir, name, output_dir, verbose): name
            for name in to_process
        }
        for future in as_completed(futures):
            name = futures[future]
            completed += 1
            print(f'{completed}: {name}', file=sys.stderr)
            rc = future.result()
            if rc != 0:
                print(f'Error code [{rc}][{name}]')
                error_count += 1
    return error_count


def parse_args():
    parser = argparse.ArgumentParser(
        description='Create the blame of files in a git repository'
    )
    parser.add_argument('repo_dir',    help='Git repository directory')
    parser.add_argument('output_dir',  help='Output directory for blame files')
    parser.add_argument('file_regexp', help='Regular expression to filter filenames')
    parser.add_argument('--revision', required=True,
                        help='Git revision/tag to blame (e.g. v6.19)')
    parser.add_argument('--blameExtension', default='.blame', dest='blame_extension',
                        help='Extension for blame output files (default: .blame)')
    parser.add_argument('--blameCommand', '--formatblame', default=DEFAULT_BLAME_COMMAND,
                        dest='blame_command',
                        help='Path to formatBlame command (default: formatBlame.pl next to this script)')
    parser.add_argument('--overwrite', action='store_true',
                        help='Reprocess files even if blame output already exists')
    parser.add_argument('--verbose', action='store_true',
                        help='Print each matched file and command to stderr')
    parser.add_argument('--jobs', '-j', type=int, default=DEFAULT_JOBS, metavar='N',
                        help=f'Number of parallel jobs (default: {DEFAULT_JOBS})')
    return parser.parse_args()


def main():
    args = parse_args()

    try:
        all_files = get_tracked_files(args.repo_dir)
    except subprocess.CalledProcessError as e:
        print(f'Unable to traverse git repo [{args.repo_dir}]: {e}', file=sys.stderr)
        sys.exit(1)

    pattern = re.compile(args.file_regexp) if args.file_regexp else None

    to_process, already_done = collect_files(
        all_files, pattern, args.repo_dir, args.output_dir,
        args.blame_extension, args.overwrite, args.verbose
    )

    error_count = run_parallel(
        to_process, args.blame_command, args.blame_extension,
        args.revision, args.repo_dir, args.output_dir, args.verbose, args.jobs
    )

    print(f'Newly processed [{len(to_process)}] Already done [{already_done}] files Error [{error_count}]')


if __name__ == '__main__':
    main()
