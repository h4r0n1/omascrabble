// A tiny test harness that runs unchanged under Node and under Qt's QML
// JavaScript engine (QV4), so the engine is verified on the runtime that
// actually ships it. No dependencies, no platform APIs.
//
// A test module exports `name` and `register(t)`; register calls
// t.test(title, fn). fn receives the runner context (fixtures such as the
// compiled dictionary text) and may call t.skip(reason).

class AssertionError extends Error {}
class SkipSignal extends Error {}

function show(v) {
  try { return JSON.stringify(v) } catch (e) { return String(v) }
}

function deepEqual(a, b) {
  if (a === b) return true
  if (typeof a !== typeof b || a === null || b === null || typeof a !== "object") return false
  if (Array.isArray(a) !== Array.isArray(b)) return false
  const ka = Object.keys(a), kb = Object.keys(b)
  if (ka.length !== kb.length) return false
  for (const k of ka) if (!deepEqual(a[k], b[k])) return false
  return true
}

export function createRunner(context) {
  const results = { passed: 0, failed: 0, skipped: 0, failures: [], log: [] }
  let currentSuite = ""
  const pending = []

  const t = {
    context: context || {},
    test(title, fn) { pending.push({ suite: currentSuite, title: title, fn: fn }) },
    ok(value, message) { if (!value) throw new AssertionError(message || "expected truthy, got " + show(value)) },
    equal(actual, expected, message) {
      if (actual !== expected) throw new AssertionError((message ? message + ": " : "") + "expected " + show(expected) + ", got " + show(actual))
    },
    deepEqual(actual, expected, message) {
      if (!deepEqual(actual, expected)) throw new AssertionError((message ? message + ": " : "") + "expected " + show(expected) + ", got " + show(actual))
    },
    throws(fn, message) {
      let threw = false
      try { fn() } catch (e) { threw = true }
      if (!threw) throw new AssertionError(message || "expected an exception")
    },
    skip(reason) { throw new SkipSignal(reason || "skipped") }
  }

  return {
    add(module) {
      currentSuite = module.name
      module.register(t)
    },
    run(filter) {
      for (const item of pending) {
        const label = item.suite + " › " + item.title
        if (filter && label.indexOf(filter) === -1) continue
        try {
          item.fn(t.context)
          results.passed++
        } catch (e) {
          if (e instanceof SkipSignal) {
            results.skipped++
            results.log.push("SKIP " + label + " (" + e.message + ")")
          } else {
            results.failed++
            const msg = e && e.message ? e.message : String(e)
            results.failures.push({ test: label, message: msg, stack: e && e.stack ? String(e.stack) : "" })
            results.log.push("FAIL " + label + ": " + msg)
          }
        }
      }
      return results
    }
  }
}
