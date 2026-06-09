// Photo masonry + lightbox for the /photos page. Initialized on each Swup page
// view (and the initial load) and torn down before each navigation so the
// window/document listeners don't stack. Replaces the former LiveView hooks,
// which don't re-mount after Swup's AJAX content swap.

let cleanups = [];

function initMasonry() {
  document.querySelectorAll(".photo-grid").forEach((grid) => {
    const buttons = Array.from(grid.querySelectorAll(".photo-button"));
    if (!buttons.length) return;

    let currentCols = 0;
    const columnCount = () => (innerWidth <= 480 ? 1 : innerWidth <= 720 ? 2 : 3);

    const layout = () => {
      const cols = columnCount();
      if (cols === currentCols) return;
      currentCols = cols;
      const columns = Array.from({ length: cols }, () => {
        const c = document.createElement("div");
        c.className = "photo-column";
        return c;
      });
      buttons.forEach((btn, i) => columns[i % cols].appendChild(btn));
      grid.replaceChildren(...columns);
    };

    let timer;
    const onResize = () => {
      clearTimeout(timer);
      timer = setTimeout(layout, 150);
    };

    layout();
    window.addEventListener("resize", onResize);
    cleanups.push(() => {
      clearTimeout(timer);
      window.removeEventListener("resize", onResize);
    });
  });
}

function initLightbox() {
  const overlay = document.getElementById("photoOverlay");
  if (!overlay) return;
  const full = overlay.querySelector(".photo-overlay-img");
  let lastFocus = null;

  const open = (img) => {
    full.src = img.src;
    full.alt = img.alt;
    lastFocus = document.activeElement;
    document.body.style.overflow = "hidden";
    overlay.removeAttribute("inert");
    overlay.classList.add("is-open");
    overlay.focus();
  };
  const close = () => {
    if (!overlay.classList.contains("is-open")) return;
    overlay.classList.remove("is-open");
    overlay.setAttribute("inert", "");
    document.body.style.overflow = "";
    if (lastFocus) lastFocus.focus();
    setTimeout(() => {
      full.src = "";
    }, 240);
  };

  const onClick = (e) => {
    const btn = e.target.closest(".photo-button");
    if (btn) open(btn.querySelector("img"));
  };
  const onKeydown = (e) => {
    if (!overlay.classList.contains("is-open")) return;
    if (e.key === "Escape") return close();
    if (e.key === "Tab") {
      e.preventDefault();
      overlay.focus();
    }
  };

  document.addEventListener("click", onClick);
  document.addEventListener("keydown", onKeydown);
  overlay.addEventListener("click", close);
  cleanups.push(() => {
    document.removeEventListener("click", onClick);
    document.removeEventListener("keydown", onKeydown);
  });
}

export function initPhotos() {
  initMasonry();
  initLightbox();
}

export function teardownPhotos() {
  cleanups.forEach((fn) => fn());
  cleanups = [];
}
