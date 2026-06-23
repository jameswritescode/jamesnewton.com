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
  const closeButton = overlay.querySelector(".photo-overlay-close");
  let lastFocus = null;
  let currentButton = null;

  // Swap the displayed image without re-opening the dialog (so lastFocus and the
  // open state are preserved across left/right navigation).
  const show = (btn) => {
    currentButton = btn;
    const img = btn.querySelector("img");
    full.src = btn.dataset.full || img.src;
    full.alt = img.alt;
  };
  const open = (btn) => {
    lastFocus = document.activeElement;
    document.body.style.overflow = "hidden";
    overlay.removeAttribute("inert");
    overlay.classList.add("is-open");
    show(btn);
    // Focus the close button so there's a keyboard-operable control in the
    // dialog (Enter/Space activates it; Esc and backdrop-click also close).
    (closeButton || overlay).focus();
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

  // Move to the previous/next photo within the gallery the current one belongs
  // to, in gallery order (data-index), wrapping around at the ends.
  const navigate = (dir) => {
    if (!currentButton) return;
    const grid = currentButton.closest(".photo-grid");
    if (!grid) return;
    const buttons = Array.from(grid.querySelectorAll(".photo-button")).sort(
      (a, b) => Number(a.dataset.index) - Number(b.dataset.index)
    );
    const i = buttons.indexOf(currentButton);
    if (i === -1) return;
    show(buttons[(i + dir + buttons.length) % buttons.length]);
  };

  const onClick = (e) => {
    const btn = e.target.closest(".photo-button");
    if (btn) open(btn);
  };
  const onKeydown = (e) => {
    if (!overlay.classList.contains("is-open")) return;
    if (e.key === "Escape") return close();
    if (e.key === "ArrowRight") {
      e.preventDefault();
      return navigate(1);
    }
    if (e.key === "ArrowLeft") {
      e.preventDefault();
      return navigate(-1);
    }
    if (e.key === "Tab") {
      // Only the close button is focusable inside the dialog, so keep focus on
      // it — this traps focus without letting it escape to the page behind.
      e.preventDefault();
      (closeButton || overlay).focus();
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
