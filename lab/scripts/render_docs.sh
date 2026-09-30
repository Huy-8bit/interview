#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
renderer_image="${MERMAID_IMAGE:-ghcr.io/mermaid-js/mermaid-cli/mermaid-cli:11.4.2}"
task_user="$(id -u):$(id -g)"

docker run --rm --network none --user "$task_user" \
  -v "$project_dir:/work" -w /work python:3.12-slim \
  python scripts/docs.py extract

docker run --rm --network none --user "$task_user" \
  -v "$project_dir/docs:/work" --entrypoint /bin/sh "$renderer_image" -c '
  set -eu
  for source in /work/diagrams/sources/*.mmd; do
    name=${source##*/}
    name=${name%.mmd}
    /home/mermaidcli/node_modules/.bin/mmdc -p /puppeteer-config.json \
      -c /work/mermaid-config.json -i "$source" \
      -o "/work/diagrams/$name.svg" -b white -q
    echo "Rendered $name"
  done
  '

docker run --rm --network none --user "$task_user" \
  -v "$project_dir:/work" -w /work python:3.12-slim \
  python scripts/docs.py seal
docker run --rm --network none --user "$task_user" \
  -v "$project_dir:/work:ro" -w /work python:3.12-slim \
  python scripts/docs.py check
