import QtQuick
import QtTest
import "../all.mjs" as All
import "../lib/harness.mjs" as Harness

// Runs every engine test suite under Qt's own JavaScript engine (QV4), the
// runtime the plugin ships on. Run with tests/run-qml.sh.
TestCase {
  name: "Engine"

  function readFixture(rel) {
    var xhr = new XMLHttpRequest()
    try {
      xhr.open("GET", Qt.resolvedUrl("../../" + rel), false)
      xhr.send()
      return xhr.status === 200 || xhr.status === 0 ? xhr.responseText : null
    } catch (e) {
      return null
    }
  }

  function test_all_suites() {
    var runner = Harness.createRunner({
      slow: true,
      openLexicon: readFixture("dictionary/data/open-fr.dawg"),
      openLexiconForms: readFixture("dictionary/data/open-fr.forms.dawg"),
      openEnglish: readFixture("dictionary/data/open-en.dawg"),
      openEnglishForms: readFixture("dictionary/data/open-en.forms.dawg")
    })
    for (var i = 0; i < All.SUITES.length; i++) runner.add(All.SUITES[i])
    var results = runner.run("")
    for (var j = 0; j < results.log.length; j++) console.log(results.log[j])
    console.log(results.passed + " passed, " + results.failed + " failed, " + results.skipped + " skipped")
    compare(results.failed, 0, results.failures.length ? results.failures[0].test + ": " + results.failures[0].message : "")
  }
}
