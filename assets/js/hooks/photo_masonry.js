// Distributes .photo-button children into N columns by viewport width.
// Ported from the prototype; runs per grid element.
export const PhotoMasonry = {
  mounted() {
    this._buttons = Array.from(this.el.querySelectorAll(".photo-button"));
    this._currentCols = 0;
    this._columnCount = () => {
      if (innerWidth <= 480) return 1;
      if (innerWidth <= 720) return 2;
      return 3;
    };
    this._layout = () => {
      const cols = this._columnCount();
      if (cols === this._currentCols) return;
      this._currentCols = cols;
      const columns = Array.from({ length: cols }, () => {
        const c = document.createElement("div");
        c.className = "photo-column";
        return c;
      });
      this._buttons.forEach((btn, i) => columns[i % cols].appendChild(btn));
      this.el.replaceChildren(...columns);
    };
    this._onResize = () => {
      clearTimeout(this._timer);
      this._timer = setTimeout(this._layout, 150);
    };
    this._layout();
    window.addEventListener("resize", this._onResize);
  },
  destroyed() {
    clearTimeout(this._timer);
    window.removeEventListener("resize", this._onResize);
  },
};
