import QtQuick
import QtTest
import "bench-movegen.mjs" as Bench
TestCase {
  name: "MoveGenBench"
  function test_bench() {
    var xhr = new XMLHttpRequest()
    xhr.open("GET", Qt.resolvedUrl("../dictionary/data/open-fr.dawg"), false)
    xhr.send()
    Bench.runBench(xhr.responseText, function(line) { console.log(line) })
  }
}
