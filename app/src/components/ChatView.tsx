import { useRef, useState } from "react";
import { HD365, PendingProposal, RunExecuteResult, RunPreview } from "../lib/bridge";
import { ProposalStatus, SolutionCard } from "./SolutionCard";
import { ExecuteConfirmModal } from "./ExecuteConfirmModal";
import { ResultPanel } from "./ResultPanel";

type ChatEntry =
  | { kind: "user"; id: string; text: string }
  | { kind: "proposal"; id: string; proposal: PendingProposal; status: ProposalStatus }
  | { kind: "result"; id: string; result: RunExecuteResult }
  | { kind: "error"; id: string; text: string };

let seq = 0;
function nextId(): string {
  seq += 1;
  return `e${seq}`;
}

export function ChatView() {
  const [entries, setEntries] = useState<ChatEntry[]>([]);
  const [input, setInput] = useState("");
  const [busy, setBusy] = useState(false);
  const [activeEntryId, setActiveEntryId] = useState<string | null>(null);
  const [editingEntryId, setEditingEntryId] = useState<string | null>(null);
  const [editedScript, setEditedScript] = useState<string | null>(null);
  const [confirm, setConfirm] = useState<{ preview: RunPreview; scriptOverride?: string } | null>(null);
  const bottomRef = useRef<HTMLDivElement | null>(null);

  function pushEntry(entry: ChatEntry) {
    setEntries((prev) => [...prev, entry]);
    setTimeout(() => {
      if (typeof bottomRef.current?.scrollIntoView === "function") {
        bottomRef.current.scrollIntoView({ behavior: "smooth" });
      }
    }, 50);
  }

  function setStatus(id: string, status: ProposalStatus) {
    setEntries((prev) =>
      prev.map((e) => (e.kind === "proposal" && e.id === id ? { ...e, status } : e))
    );
  }

  async function handleSend() {
    const text = input.trim();
    if (!text || busy) return;
    setInput("");
    pushEntry({ kind: "user", id: nextId(), text });
    setBusy(true);
    try {
      const proposal = await HD365.submitPipeline(text);
      const id = nextId();
      pushEntry({ kind: "proposal", id, proposal, status: "pending" });
      setActiveEntryId(id);
      setEditingEntryId(null);
      setEditedScript(null);
    } catch (e) {
      pushEntry({ kind: "error", id: nextId(), text: String(e) });
    } finally {
      setBusy(false);
    }
  }

  async function handleRunClick(entryId: string) {
    setBusy(true);
    try {
      const override = editedScript ?? undefined;
      const preview = await HD365.runPreview(override);
      if (!preview.HasPending) {
        pushEntry({ kind: "error", id: nextId(), text: "Nothing pending to run." });
        return;
      }
      if (preview.RequiresConfirmation) {
        setConfirm({ preview, scriptOverride: override });
      } else {
        await doExecute(entryId, undefined, override);
      }
    } catch (e) {
      pushEntry({ kind: "error", id: nextId(), text: String(e) });
    } finally {
      setBusy(false);
    }
  }

  async function doExecute(entryId: string, confirmPhrase?: string, scriptOverride?: string) {
    setBusy(true);
    try {
      const result = await HD365.runExecute(confirmPhrase, scriptOverride);
      pushEntry({ kind: "result", id: nextId(), result });
      setStatus(entryId, "executed");
      setActiveEntryId(null);
      setEditingEntryId(null);
      setEditedScript(null);
      setConfirm(null);
    } catch (e) {
      pushEntry({ kind: "error", id: nextId(), text: String(e) });
      setConfirm(null);
    } finally {
      setBusy(false);
    }
  }

  async function handleCancel(entryId: string) {
    setBusy(true);
    try {
      await HD365.runCancel();
    } catch {
      // Best-effort - clear client state regardless.
    }
    setStatus(entryId, "cancelled");
    setActiveEntryId(null);
    setEditingEntryId(null);
    setEditedScript(null);
    setBusy(false);
  }

  function handleCopy(proposal: PendingProposal) {
    const text = (editedScript ?? proposal.ExecutionScript ?? "").trim();
    navigator.clipboard?.writeText(text).catch(() => {});
  }

  function handleToggleEdit(entryId: string, proposal: PendingProposal) {
    if (editingEntryId === entryId) {
      setEditingEntryId(null);
    } else {
      setEditedScript(editedScript ?? proposal.ExecutionScript ?? "");
      setEditingEntryId(entryId);
    }
  }

  return (
    <div className="chat-view">
      <div className="chat-transcript">
        {entries.length === 0 && (
          <p className="chat-empty">
            Describe an M365 helpdesk task in plain language, e.g. "create security groups for
            every department and nest an Accounts Payable group under each".
          </p>
        )}
        {entries.map((entry) => {
          if (entry.kind === "user") {
            return (
              <div key={entry.id} className="chat-bubble user-bubble">
                {entry.text}
              </div>
            );
          }
          if (entry.kind === "proposal") {
            return (
              <SolutionCard
                key={entry.id}
                proposal={entry.proposal}
                status={entry.status}
                isActive={entry.id === activeEntryId}
                editing={entry.id === editingEntryId}
                editedScript={entry.id === activeEntryId ? editedScript : null}
                busy={busy}
                onEditChange={setEditedScript}
                onToggleEdit={() => handleToggleEdit(entry.id, entry.proposal)}
                onCopy={() => handleCopy(entry.proposal)}
                onCancel={() => handleCancel(entry.id)}
                onRun={() => handleRunClick(entry.id)}
              />
            );
          }
          if (entry.kind === "result") {
            return <ResultPanel key={entry.id} result={entry.result} />;
          }
          return (
            <div key={entry.id} className="chat-bubble error-bubble">
              {entry.text}
            </div>
          );
        })}
        <div ref={bottomRef} />
      </div>

      <form
        className="chat-input-row"
        onSubmit={(e) => {
          e.preventDefault();
          handleSend();
        }}
      >
        <input
          className="chat-input"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          placeholder="Describe a task..."
          disabled={busy}
        />
        <button type="submit" className="btn-primary" disabled={busy || !input.trim()}>
          {busy ? "Working..." : "Send"}
        </button>
      </form>

      {confirm && (
        <ExecuteConfirmModal
          preview={confirm.preview}
          busy={busy}
          onConfirm={(phrase) => {
            if (activeEntryId) void doExecute(activeEntryId, phrase, confirm.scriptOverride);
          }}
          onCancel={() => setConfirm(null)}
        />
      )}
    </div>
  );
}
