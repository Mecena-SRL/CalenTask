#!/bin/bash
# Avvia CalenTask in diversi stati e controlla che resti viva.
# Uso: smoke-launch.sh /percorso/CalenTask.app
set -u
APP="$1"
BIN="$APP/Contents/MacOS/CalenTask"
BUNDLE_ID="it.mecena.CalenTask"
OUT="smoke"
REPORTS="$HOME/Library/Logs/DiagnosticReports"
mkdir -p "$OUT"
sw_vers
system_profiler SPDisplaysDataType 2>/dev/null | grep -E "Resolution|Display Type" || true

failures=0

# $1 = nome scenario, $2 = secondi di osservazione
run_scenario() {
  local name="$1" seconds="$2"
  echo "::group::Scenario $name"
  local log="$OUT/$name-log.txt"
  log stream --style compact --level debug \
    --predicate 'process == "CalenTask"' > "$log" 2>&1 &
  local logpid=$!
  sleep 1
  "$BIN" > "$OUT/$name-stdout.txt" 2>&1 &
  local pid=$!
  local alive=1
  for i in $(seq 1 "$seconds"); do
    sleep 1
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "❌ $name: l'app è terminata dopo ${i}s"
      alive=0
      break
    fi
    if [ "$i" -eq 8 ] || [ "$i" -eq "$seconds" ]; then
      screencapture -x "$OUT/$name-${i}s.png" 2>/dev/null || true
    fi
  done
  if [ "$alive" -eq 1 ]; then
    # Viva, ma reattiva? Un main thread bloccato non risponde ad AppleScript.
    if osascript -e "with timeout of 10 seconds" -e "tell application id \"$BUNDLE_ID\" to get name" -e "end timeout" >/dev/null 2>&1; then
      echo "✅ $name: viva e reattiva dopo ${seconds}s"
    else
      echo "⚠️ $name: viva ma NON risponde (main thread bloccato?)"
      sample "$pid" 5 -file "$OUT/$name-sample.txt" >/dev/null 2>&1 || true
      head -120 "$OUT/$name-sample.txt" 2>/dev/null || true
      alive=0
    fi
    kill "$pid" 2>/dev/null
    sleep 2
    kill -9 "$pid" 2>/dev/null
  fi
  kill "$logpid" 2>/dev/null
  echo "--- eccezioni / vincoli dal log ($name) ---"
  grep -iE "exception|constraint|terminating|fault|crash|assert" "$log" | head -60 || true
  echo "::endgroup::"
  if [ "$alive" -eq 0 ]; then failures=$((failures + 1)); fi
}

reset_state() {
  defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
  rm -rf "$HOME/Library/Application Support/default.store"* \
         "$HOME/Library/Saved Application State/$BUNDLE_ID.savedState" 2>/dev/null || true
}

# 1 — Primo avvio, stato pulito.
reset_state
run_scenario "primo-avvio" 45

# 2 — Secondo avvio: benvenuto già visto, store esistente.
run_scenario "secondo-avvio" 45

# 3 — Finestra grande (pannello Oggi) e pagine di partenza diverse.
for page in calendar today quick; do
  defaults write "$BUNDLE_ID" didShowWelcome -bool true
  defaults write "$BUNDLE_ID" "NSWindow Frame main" "0 0 1600 1000 0 0 1920 1080 "
  # Tutti i moduli e le funzioni accesi: più viste montate, più copertura.
  cfg=$(printf '{"modules":["activities","projects","people","insights","production"],"features":["calendarAdvancedViews","calendarWeather","calendarSummary","calendarUnscheduled","sidebarMiniCalendar","todayInspector","smartLists","tags","externalRequests","dashboardMetrics"],"startPage":"%s","moduleOrderRaw":[]}' "$page")
  defaults write "$BUNDLE_ID" app.configuration.v1 "$cfg"
  run_scenario "pagina-$page" 30
done

echo "=== Crash report ==="
ls -la "$REPORTS" 2>/dev/null | grep -i calentask || echo "(nessuno)"
for f in "$REPORTS"/CalenTask*; do
  [ -f "$f" ] || continue
  cp "$f" "$OUT/" 2>/dev/null
  echo "----- $f -----"
  head -150 "$f"
done

if [ "$failures" -gt 0 ]; then
  echo "❌ Scenari falliti: $failures"
  exit 1
fi
echo "✅ Tutti gli scenari superati"
