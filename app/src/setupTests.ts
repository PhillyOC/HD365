import "@testing-library/jest-dom/vitest";

// jsdom doesn't implement scrollIntoView; ChatView calls it defensively, but stub it too so
// any future component relying on it doesn't need its own guard just to be testable.
if (typeof Element !== "undefined" && !Element.prototype.scrollIntoView) {
  Element.prototype.scrollIntoView = () => {};
}
