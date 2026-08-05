import std/[os, algorithm]
import report/[parser, output_table, output_svg, output_plot]

const siteDir = "site"

proc csvFiles(): seq[string] =
  result = commandLineParams()
  if result.len > 0:
    return

  for csvFile in walkFiles("*.csv"):
    result.add(csvFile)
  result.sort()

let report = parseFiles(csvFiles())

if report.suites.len == 0:
  echo "No benchmark CSVs found"
  quit(1)

let table = renderTable(report)

echo ""
echo table

createDir(siteDir)
writeFile(siteDir / "summary.txt", table & "\n")
writeFile(siteDir / "benchmarks.svg", renderSvg(report) & "\n")
report.saveTimePlot(siteDir / "time.svg")
