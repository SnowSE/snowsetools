// Global keyboard shortcut: Ctrl+K or / focuses the schedule search input
const handler = (e) => {
  if (
    (e.ctrlKey && e.key === "k") ||
    (e.key === "/" && !(e.target instanceof HTMLInputElement ||
                        e.target instanceof HTMLTextAreaElement ||
                        e.target instanceof HTMLSelectElement))
  ) {
    const el = document.getElementById("scheduling-search-input");
    if (el) {
      e.preventDefault();
      el.focus();
    }
  }
};

window.addEventListener("keydown", handler);
