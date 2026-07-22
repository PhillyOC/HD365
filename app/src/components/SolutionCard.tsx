import { PendingProposal } from "../lib/bridge";

export type ProposalStatus = "pending" | "executed" | "cancelled";

interface SolutionCardProps {
  proposal: PendingProposal;
  status: ProposalStatus;
  isActive: boolean;
  editing: boolean;
  editedScript: string | null;
  busy: boolean;
  onEditChange: (text: string) => void;
  onToggleEdit: () => void;
  onCopy: () => void;
  onCancel: () => void;
  onRun: () => void;
}

export function SolutionCard({
  proposal,
  status,
  isActive,
  editing,
  editedScript,
  busy,
  onEditChange,
  onToggleEdit,
  onCopy,
  onCancel,
  onRun,
}: SolutionCardProps) {
  const scriptText = editedScript ?? proposal.ExecutionScript ?? "";
  const isWrite = Boolean(proposal.Proposal?.isWrite) || Boolean(proposal.BulkKind);
  const warnings = proposal.Proposal?.warnings ?? [];
  const opCount = proposal.JobData?.CreateCount;

  return (
    <div className={`solution-card ${isActive && status === "pending" ? "active" : "resolved"}`}>
      <p className="solution-summary">
        {proposal.SolutionSummary || proposal.Proposal?.summary || "(no summary)"}
      </p>

      {warnings.length > 0 && (
        <ul className="warnings">
          {warnings.map((w, i) => (
            <li key={i}>{w}</li>
          ))}
        </ul>
      )}

      <div className="meta-row">
        {proposal.Proposal?.platform && <span>Platform: {proposal.Proposal.platform}</span>}
        <span className={isWrite ? "badge badge-write" : "badge badge-read"}>
          {isWrite ? "WRITE" : "READ"}
        </span>
        {typeof opCount === "number" && opCount > 0 && <span>{opCount} operation(s)</span>}
      </div>

      {editing ? (
        <textarea
          className="script-edit"
          value={scriptText}
          onChange={(e) => onEditChange(e.target.value)}
          rows={4}
          spellCheck={false}
        />
      ) : (
        <pre className="script-preview">{scriptText}</pre>
      )}

      {status === "pending" && isActive ? (
        <div className="solution-actions">
          <button onClick={onCopy} disabled={busy}>
            Copy
          </button>
          <button onClick={onToggleEdit} disabled={busy}>
            {editing ? "Done editing" : "Edit"}
          </button>
          <button className="btn-cancel" onClick={onCancel} disabled={busy}>
            Cancel
          </button>
          <button className="btn-primary" onClick={onRun} disabled={busy}>
            Run
          </button>
        </div>
      ) : (
        <div className={`solution-status status-${status}`}>
          {status === "executed" ? "Executed" : status === "cancelled" ? "Cancelled" : ""}
        </div>
      )}
    </div>
  );
}
