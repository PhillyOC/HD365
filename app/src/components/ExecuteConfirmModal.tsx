import { useState } from "react";
import { RunPreview } from "../lib/bridge";

interface ExecuteConfirmModalProps {
  preview: RunPreview;
  busy: boolean;
  onConfirm: (phrase: string) => void;
  onCancel: () => void;
}

/** GUI equivalent of the console's red write-warning box + typed-EXECUTE prompt. */
export function ExecuteConfirmModal({ preview, busy, onConfirm, onCancel }: ExecuteConfirmModalProps) {
  const [phrase, setPhrase] = useState("");
  const expected = preview.ConfirmationPhrase ?? "EXECUTE";
  const matches = phrase.trim().toLowerCase() === expected.toLowerCase();

  return (
    <div className="modal-overlay">
      <div className="modal">
        <div className="warning-banner">
          <strong>WRITE EXECUTION WARNING</strong>
          <p>This will make LIVE CHANGES in your Microsoft tenant.</p>
          <p>An immutable audit record will be written locally.</p>
        </div>

        {typeof preview.OperationCount === "number" && preview.OperationCount > 0 && (
          <p className="op-count">Operations: {preview.OperationCount}</p>
        )}

        <pre className="script-preview">{preview.ScriptText}</pre>

        <label className="confirm-label">
          Type <code>{expected}</code> to confirm:
          <input
            className="confirm-input"
            aria-label="confirmation phrase"
            value={phrase}
            onChange={(e) => setPhrase(e.target.value)}
            autoFocus
            onKeyDown={(e) => {
              if (e.key === "Enter" && matches && !busy) onConfirm(phrase);
            }}
          />
        </label>

        <div className="modal-actions">
          <button className="btn-cancel" onClick={onCancel} disabled={busy}>
            Cancel
          </button>
          <button
            className="btn-danger"
            onClick={() => onConfirm(phrase)}
            disabled={!matches || busy}
          >
            Confirm &amp; Run
          </button>
        </div>
      </div>
    </div>
  );
}
