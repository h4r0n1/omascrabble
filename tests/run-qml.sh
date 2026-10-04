#!/bin/bash
# Runs the engine suites under Qt 6's QML engine, headless.
# Needs qt6-declarative (qmltestrunner). Reading the dictionary fixture from
# disk needs QML_XHR_ALLOW_FILE_READ for this test process only; the plugin
# itself never uses XMLHttpRequest.
set -euo pipefail
cd "$(dirname "$0")/.."
runner=/usr/lib/qt6/bin/qmltestrunner
[[ -x $runner ]] || runner=$(command -v qmltestrunner6 || command -v qmltestrunner)
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 "$runner" -input tests/qml "$@"
