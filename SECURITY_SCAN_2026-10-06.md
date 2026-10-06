# CalenTask — Security Scan Report
**Data**: 2026-10-06  
**Codebase**: 163 Swift files, ~32K LOC  
**Autore**: Claude Haiku 4.5 (Automated Security Analysis)

---

## Executive Summary

**Scansione completa del codice** identificate 7 aree critiche di sicurezza. Nessuna vulnerabilità CRITICA di data leakage, ma multipli **crash risks** e **missing validations** che potrebbero essere sfruttati.

### Risk Summary
| Severity | Count | Issues |
|----------|-------|--------|
| 🔴 CRITICAL | 1 | #62: `try!` crash risks in PreviewSampleData.swift |
| 🟠 HIGH | 1 | #63: Force unwrapping in production code |
| 🟡 MEDIUM | 4 | #64-67: Input validation, token storage, CloudKit sync, logging |
| 🟢 LOW | 1 | #68: Defensive programming practices |

---

## Detailed Findings

### 1. ❌ CRITICAL: Unrecoverable Errors (`try!`)
**Issue**: #62  
**Locations**:
- `CalenTask/Support/PreviewSampleData.swift:23` — ModelContainer init
- `CalenTask/Support/PreviewSampleData.swift:26` — SeedService
- `CalenTask/Support/PreviewSampleData.swift:70` — context.save()

**Impact**: App crash if initialization fails, no recovery.  
**Fix**: Replace with `do-catch` + error logging.

---

### 2. 🚫 HIGH: Force Unwrapping in Production
**Issue**: #63  
**Locations**:
- `DSPalette.swift`: `randomElement()!` — crash if empty array
- `CustomFieldValueRow.swift`: `value!.valueRaw` — unsafe optional handling
- `ProjectGanttView.swift`: `dateInterval()!.end` — nil handling

**Impact**: Runtime crashes on edge cases (rare but possible).  
**Fix**: Use optional chaining & guard statements.

---

### 3. ⚠️ MEDIUM: Input Validation Missing
**Issue**: #64  
**Scope**: Across codebase:
- `NaturalDateParser.swift` — No input length limits, ReDoS risk
- UI capture fields — No sanitization
- JSON deserialization — 70 points, no schema validation

**Impact**: DoS potential, data corruption, injection risks.  
**Fix**: Add input limits, whitelist validation, timeout guards.

---

### 4. 🔑 MEDIUM: GitHub Token Security
**Issue**: #65  
**Findings**:
- ✓ Uses Keychain (correct)
- ✗ Token in Authorization header (exposure risk)
- ✗ No token expiry/rotation
- ✗ DMG saved in public Downloads folder
- ✗ Shell invocation for app launch (fragile)

**Fix**: Add token timeout, encrypt DMG, use NSWorkspace.

---

### 5. ☁️ MEDIUM: CloudKit Sync Security
**Issue**: #66  
**Scope**: Multidevice sync via iCloud container `iCloud.it.mecena.CalenTask`
- Soft delete filter not enforced across all queries
- Error handling is silent (user doesn't know if data is synced)
- No end-to-end encryption
- Conflict resolution is basic

**Fix**: Model validator, user sync feedback, encryption, audit trail.

---

### 6. 📝 MEDIUM: Sensitive Data in Logs
**Issue**: #67  
**Locations**:
- `CalenTaskApp.swift:84,105` — `.privacy: .public` on error logs
- Potential for log leakage to crash reporters

**Impact**: Information disclosure if logs are collected.  
**Fix**: Use `.privacy: .private` by default, sanitize error messages.

---

### 7. 🛡️ LOW: Defensive Programming
**Issue**: #68  
**Scope**: General resilience
- Regex `try!` compile
- No invariant checking on models
- No memory leak testing
- Missing error recovery

**Fix**: Use compile-time regex, add model validators, memory tests.

---

## Security Scorecard

| Category | Status | Notes |
|----------|--------|-------|
| **Crash Safety** | ⚠️ NEEDS WORK | 4+ crash risks from force unwrap / try! |
| **Input Validation** | ⚠️ NEEDS WORK | Missing limits, no sanitization |
| **Secrets Management** | ✅ GOOD | Keychain used correctly |
| **Encryption** | ⚠️ PARTIAL | HTTPS for net, no at-rest encryption |
| **Error Handling** | ⚠️ NEEDS WORK | Silent failures, data leakage in logs |
| **Code Quality** | ✅ GOOD | Well-structured, clear patterns |

---

## GitHub Issues Created

| # | Title | Severity |
|---|-------|----------|
| [#62](#62) | Crash risk: `try!` in PreviewSampleData.swift | 🔴 CRITICAL |
| [#63](#63) | Crash risk: Force unwrapping in production | 🟠 HIGH |
| [#64](#64) | Input validation missing | 🟡 MEDIUM |
| [#65](#65) | GitHub token storage audit | 🟡 MEDIUM |
| [#66](#66) | CloudKit sync security review | 🟡 MEDIUM |
| [#67](#67) | Sensitive data in logs | 🟡 MEDIUM |
| [#68](#68) | Crash resilience & defensive programming | 🟢 LOW |

---

## Remediation Priority

### Phase 1 (Immediate)
1. Fix #62 (`try!` crashes) — 1 hour
2. Fix #63 (force unwrapping) — 2 hours

### Phase 2 (This Sprint)
3. Fix #67 (logging privacy) — 1 hour
4. Fix #64 (input validation) — 3-4 hours

### Phase 3 (Next Sprint)
5. Fix #65 (token security) — 2 hours
6. Fix #66 (CloudKit audit) — 4-5 hours
7. Fix #68 (defensive programming) — 3 hours

---

## Assurance Notes

✅ **No Critical Data Leaks Found**  
✅ **Keychain Usage Is Correct**  
✅ **CloudKit Private Database Configured**  
✅ **HTTPS All Network Calls**  

⚠️ **Risk Vectors Identified**: Crash DoS, silent sync failures, input edge cases.

---

## Scanning Methodology

1. Pattern matching for `try!`, force unwrapping, `print()` statements
2. Keychain, encryption, token storage verification
3. CloudKit configuration and sync patterns
4. Input validation gaps in parsers (regex, JSON)
5. Error handling and logging for sensitive data
6. Code review of critical paths (app init, sync, auth)

**Tools Used**: grep, ripgrep, Bash analysis  
**Scope**: Full codebase (163 files)

---

Generated by Claude Code Security Review  
Session: https://claude.ai/code/session_01Ws1Pc8c1N9in8indmmcLrM
