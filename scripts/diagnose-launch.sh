#!/bin/bash
# Avvia l'app installata e ne raccoglie eccezioni, crash report, un sample
# del main thread se si blocca e uno screenshot. Non tocca dati né preferenze.
#
# Uso:   scripts/diagnose-launch.sh [/Applications/CalenTask.app]
# Risultati in ./smoke/ (mandali insieme all'output del terminale).
cd "$(dirname "$0")/.."
exec bash .github/scripts/smoke-launch.sh "${1:-/Applications/CalenTask.app}"
