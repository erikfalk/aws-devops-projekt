#!/bin/bash -ex
if pgrep flask >/dev/null; then
  echo "Process flask exists, killing it..."
  pkill flask
else
  echo "Process flask does not exist."
fi