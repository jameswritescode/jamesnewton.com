// Ported from the prototype ripple.js — a dot-matrix canvas with an expanding
// ripple and a Konami "bloom" mode. Logic is unchanged; lifecycle is managed by
// the LiveView hook so it cleans up on navigation.
export const RippleCanvas = {
  mounted() {
    const canvas = this.el;
    const ctx = canvas.getContext("2d");

    const DOT_SPACING = 20, DOT_RADIUS = 1.5, BASE_OPACITY = 0.06;
    const RIPPLE_PEAK_OPACITY = 0.3, CYCLE_DURATION = 8000, RIPPLE_WIDTH = 150;
    const BLOOM_SIGMA = 140, BLOOM_DURATION = 3600, BLOOM_SPAWN_INTERVAL = 720;
    const BLOOM_BASE_ALPHA = 0.18, BLOOM_PEAK_ALPHA = 1;

    let width, height, cols, rows, maxDist;
    const ripples = [];
    const blooms = [];
    let lastBloomSpawn = -Infinity;
    let konamiMode = false;
    const KONAMI_SEQUENCE = ["ArrowUp","ArrowUp","ArrowDown","ArrowDown","ArrowLeft","ArrowRight","ArrowLeft","ArrowRight","b","a"];
    let konamiProgress = 0;

    const resize = () => {
      width = canvas.width = window.innerWidth;
      height = canvas.height = window.innerHeight;
      cols = Math.ceil(width / DOT_SPACING) + 1;
      rows = Math.ceil(height / DOT_SPACING) + 1;
      maxDist = Math.sqrt(width * width + height * height);
    };
    const spawnRipple = (t) => ripples.push({ originX: Math.random()*width, originY: Math.random()*height, startTime: t });
    const spawnBloom = (t) => { blooms.push({ centerX: Math.random()*width, centerY: Math.random()*height, startTime: t }); lastBloomSpawn = t; };

    const draw = (timestamp) => {
      const style = getComputedStyle(document.documentElement);
      const bg = style.getPropertyValue("--bg").trim();
      const dot = style.getPropertyValue("--dot").trim();
      const baseOpacity = parseFloat(style.getPropertyValue("--dot-base-opacity").trim()) || BASE_OPACITY;
      const ripplePeakOpacity = parseFloat(style.getPropertyValue("--ripple-peak-opacity").trim()) || RIPPLE_PEAK_OPACITY;

      ctx.clearRect(0, 0, width, height);
      ctx.fillStyle = bg;
      ctx.fillRect(0, 0, width, height);

      if (konamiMode) {
        for (let i = blooms.length - 1; i >= 0; i--) {
          if (timestamp - blooms[i].startTime >= BLOOM_DURATION) blooms.splice(i, 1);
        }
        if (timestamp - lastBloomSpawn >= BLOOM_SPAWN_INTERVAL) spawnBloom(timestamp);
        const activeBlooms = blooms.map((b) => {
          const t01 = (timestamp - b.startTime) / BLOOM_DURATION;
          const s = Math.sin(Math.PI * t01);
          return { x: b.centerX, y: b.centerY, intensity: s * s };
        });
        const bloomSigmaSq2 = 2 * BLOOM_SIGMA * BLOOM_SIGMA;
        const bloomCutoffSq = (BLOOM_SIGMA * 3) * (BLOOM_SIGMA * 3);
        const alphaSpan = BLOOM_PEAK_ALPHA - BLOOM_BASE_ALPHA;
        for (let row = 0; row < rows; row++) {
          for (let col = 0; col < cols; col++) {
            const x = col * DOT_SPACING, y = row * DOT_SPACING;
            let boost = 0;
            for (const b of activeBlooms) {
              const dx = x - b.x, dy = y - b.y, distSq = dx*dx + dy*dy;
              if (distSq > bloomCutoffSq) continue;
              boost += b.intensity * Math.exp(-distSq / bloomSigmaSq2);
            }
            if (boost > 1) boost = 1;
            const alpha = BLOOM_BASE_ALPHA + alphaSpan * boost;
            const hue = (col * 47 + row * 137) % 360;
            ctx.beginPath();
            ctx.arc(x, y, DOT_RADIUS, 0, Math.PI * 2);
            ctx.fillStyle = `hsla(${hue}, 90%, 60%, ${alpha})`;
            ctx.fill();
          }
        }
      } else {
        for (let i = ripples.length - 1; i >= 0; i--) {
          if ((timestamp - ripples[i].startTime) / CYCLE_DURATION >= 1) ripples.splice(i, 1);
        }
        if (ripples.length === 0) spawnRipple(timestamp);
        const active = ripples.map((r) => ({
          originX: r.originX, originY: r.originY,
          rippleRadius: Math.min((timestamp - r.startTime) / CYCLE_DURATION, 1) * (maxDist + RIPPLE_WIDTH),
        }));
        const sigmaSq2 = 2 * (RIPPLE_WIDTH / 3) * (RIPPLE_WIDTH / 3);
        const halfWidth = RIPPLE_WIDTH / 2;
        for (let row = 0; row < rows; row++) {
          for (let col = 0; col < cols; col++) {
            const x = col * DOT_SPACING, y = row * DOT_SPACING;
            let totalEffect = 0, behindAny = false;
            for (const r of active) {
              const dx = x - r.originX, dy = y - r.originY, dist = Math.sqrt(dx*dx + dy*dy);
              if (dist > r.rippleRadius + halfWidth) continue;
              behindAny = true;
              const distFromRing = Math.abs(dist - r.rippleRadius);
              totalEffect += Math.exp(-(distFromRing * distFromRing) / sigmaSq2);
            }
            const combinedEffect = totalEffect > 1 ? 1 : totalEffect;
            const opacity = behindAny ? baseOpacity + (ripplePeakOpacity - baseOpacity) * combinedEffect : baseOpacity;
            ctx.beginPath();
            ctx.arc(x, y, DOT_RADIUS, 0, Math.PI * 2);
            ctx.fillStyle = `rgba(${dot}, ${opacity})`;
            ctx.fill();
          }
        }
      }
      this._raf = requestAnimationFrame(draw);
    };

    this._onKonami = (event) => {
      const key = event.key.length === 1 ? event.key.toLowerCase() : event.key;
      const expected = KONAMI_SEQUENCE[konamiProgress];
      if (key === expected) {
        konamiProgress++;
        if (konamiProgress === KONAMI_SEQUENCE.length) {
          konamiMode = !konamiMode;
          konamiProgress = 0;
          if (konamiMode) { blooms.length = 0; lastBloomSpawn = -Infinity; }
        }
      } else {
        konamiProgress = key === KONAMI_SEQUENCE[0] ? 1 : 0;
      }
    };
    // Paint the dot matrix once, with no ripple and no animation loop.
    const renderStatic = () => {
      const style = getComputedStyle(document.documentElement);
      const bg = style.getPropertyValue("--bg").trim();
      const dot = style.getPropertyValue("--dot").trim();
      const baseOpacity =
        parseFloat(style.getPropertyValue("--dot-base-opacity").trim()) || BASE_OPACITY;

      ctx.clearRect(0, 0, width, height);
      ctx.fillStyle = bg;
      ctx.fillRect(0, 0, width, height);
      for (let row = 0; row < rows; row++) {
        for (let col = 0; col < cols; col++) {
          ctx.beginPath();
          ctx.arc(col * DOT_SPACING, row * DOT_SPACING, DOT_RADIUS, 0, Math.PI * 2);
          ctx.fillStyle = `rgba(${dot}, ${baseOpacity})`;
          ctx.fill();
        }
      }
    };

    const startAnimation = () => {
      cancelAnimationFrame(this._raf);
      this._raf = requestAnimationFrame(draw);
    };
    const stopAnimation = () => {
      cancelAnimationFrame(this._raf);
      this._raf = null;
      renderStatic();
    };

    // Honor prefers-reduced-motion: keep the dot matrix, drop the motion.
    const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
    const applyMotionPreference = () =>
      reduceMotion.matches ? stopAnimation() : startAnimation();

    this._reduceMotion = reduceMotion;
    this._onMotionChange = applyMotionPreference;
    this._onResize = () => {
      resize();
      if (reduceMotion.matches) renderStatic();
    };

    window.addEventListener("resize", this._onResize);
    window.addEventListener("keydown", this._onKonami);
    reduceMotion.addEventListener("change", this._onMotionChange);
    resize();
    applyMotionPreference();
  },

  destroyed() {
    cancelAnimationFrame(this._raf);
    window.removeEventListener("resize", this._onResize);
    window.removeEventListener("keydown", this._onKonami);
    this._reduceMotion.removeEventListener("change", this._onMotionChange);
  },
};
