// Shared site behavior: theme, mobile nav, tabs, copy buttons and doc TOC scrollspy.
const root = document.documentElement;

function setTheme(theme) {
  root.dataset.theme = theme;
  try { localStorage.setItem("lutez-theme", theme); } catch {}
  document.querySelectorAll(".theme-toggle").forEach((b) => {
    b.setAttribute("aria-label", theme === "dark" ? "Switch to light theme" : "Switch to dark theme");
  });
}

document.querySelectorAll(".theme-toggle").forEach((button) => {
  button.addEventListener("click", () => setTheme(root.dataset.theme === "dark" ? "light" : "dark"));
});
setTheme(root.dataset.theme || "dark");

const navToggle = document.querySelector(".nav-toggle");
const nav = document.querySelector(".nav");
if (navToggle && nav) {
  navToggle.addEventListener("click", () => {
    const open = nav.classList.toggle("is-open");
    navToggle.setAttribute("aria-expanded", String(open));
  });
}

// Code tabs
document.querySelectorAll("[data-tabs]").forEach((group) => {
  const tabs = [...group.querySelectorAll(".code-tab")];
  const panels = [...group.querySelectorAll(".code-panel")];
  const activate = (id) => {
    tabs.forEach((t) => {
      const on = t.dataset.tab === id;
      t.classList.toggle("is-active", on);
      t.setAttribute("aria-selected", String(on));
    });
    panels.forEach((p) => p.classList.toggle("is-active", p.dataset.panel === id));
  };
  tabs.forEach((tab) => tab.addEventListener("click", () => activate(tab.dataset.tab)));
});

// Copy buttons on code blocks
function addCopyButtons(scope = document) {
  scope.querySelectorAll("pre").forEach((pre) => {
    if (pre.closest(".code-card") || pre.parentElement?.classList.contains("code-block-wrap")) return;
    const wrapper = document.createElement("div");
    wrapper.className = "code-block-wrap";
    pre.replaceWith(wrapper);
    wrapper.appendChild(pre);
    const button = document.createElement("button");
    button.type = "button";
    button.className = "copy-btn";
    button.textContent = "Copy";
    button.addEventListener("click", async () => {
      try {
        await navigator.clipboard.writeText(pre.innerText);
        button.textContent = "Copied";
      } catch {
        button.textContent = "Failed";
      }
      setTimeout(() => (button.textContent = "Copy"), 1400);
    });
    wrapper.appendChild(button);
  });
}
addCopyButtons();

// TOC scrollspy
const tocLinks = [...document.querySelectorAll(".toc-list a")];
if (tocLinks.length) {
  const targets = tocLinks
    .map((a) => document.getElementById(decodeURIComponent(a.hash.slice(1))))
    .filter(Boolean);
  const visible = new Map();
  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => visible.set(entry.target.id, entry.isIntersecting));
      const active = targets.find((t) => visible.get(t.id));
      tocLinks.forEach((a) => a.classList.toggle("is-active", active && a.hash === `#${active.id}`));
    },
    { rootMargin: "-90px 0px -65% 0px", threshold: 0 },
  );
  targets.forEach((t) => observer.observe(t));
}
