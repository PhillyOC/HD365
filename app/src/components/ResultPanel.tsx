import { RunExecuteResult } from "../lib/bridge";

export function ResultPanel({ result }: { result: RunExecuteResult }) {
  return (
    <div className="result-panel">
      <div className="result-header">Result{result.BulkKind ? ` (${result.BulkKind})` : ""}</div>
      {result.Output === null || result.Output === undefined ? (
        <p className="result-empty">(Command completed with no pipeline output.)</p>
      ) : (
        <pre className="result-output">{JSON.stringify(result.Output, null, 2)}</pre>
      )}
    </div>
  );
}
