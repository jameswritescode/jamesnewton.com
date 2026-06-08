// Lightbox overlay. Opens the full image, traps focus, restores on close.
// Attached to #photoOverlay; binds a delegated click for .photo-button.
export const PhotoLightbox = {
  mounted() {
    const overlay = this.el;
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
      setTimeout(() => { full.src = ""; }, 240);
    };

    this._onClick = (e) => {
      const btn = e.target.closest(".photo-button");
      if (btn) open(btn.querySelector("img"));
    };
    this._onKeydown = (e) => {
      if (!overlay.classList.contains("is-open")) return;
      if (e.key === "Escape") return close();
      if (e.key === "Tab") { e.preventDefault(); overlay.focus(); }
    };
    this._onOverlayClick = close;

    document.addEventListener("click", this._onClick);
    document.addEventListener("keydown", this._onKeydown);
    overlay.addEventListener("click", this._onOverlayClick);
  },
  destroyed() {
    document.removeEventListener("click", this._onClick);
    document.removeEventListener("keydown", this._onKeydown);
  },
};
