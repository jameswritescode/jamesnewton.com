// Ported from the prototype ripple.js — a dot-matrix canvas with an expanding
// ripple and a Konami "bloom" mode. Logic is unchanged; lifecycle is managed by
// the LiveView hook so it cleans up on navigation.
// Sampled feature points (canvas pixels) for a sad face centred on the viewport.
// Eyes are two points above centre; the mouth is a wide circular arc (a rounded
// frown: high in the middle, corners drooping). Pure so it can be unit-tested.
export function frownPoints(width, height) {
  const cx = width / 2;
  const cy = height / 2; // centred
  const s = Math.min(width, height) * 0.85; // overall face scale
  const eyes = [
    { x: cx - s * 0.28, y: cy - s * 0.22 },
    { x: cx + s * 0.28, y: cy - s * 0.22 },
  ];
  // A large radius relative to the width keeps the frown wide and gently rounded
  // rather than a sharp parabola; the arc's circle sits below the mouth so the
  // middle is the high point and the corners droop.
  const mouthWidth = s * 0.95;
  const radius = mouthWidth * 0.75;
  const mouthTop = cy + s * 0.2; // y of the mouth's high (middle) point
  const arcCenterY = mouthTop + radius;
  const phi = Math.asin(mouthWidth / 2 / radius); // half-angle subtended
  const N = 13;
  const mouth = [];
  for (let i = 0; i < N; i++) {
    const t = i / (N - 1);
    const angle = -phi + t * 2 * phi;
    mouth.push({ x: cx + radius * Math.sin(angle), y: arcCenterY - radius * Math.cos(angle) });
  }
  return { eyes, mouth };
}

export const RippleCanvas = {
  mounted() {
    const canvas = this.el;
    const ctx = canvas.getContext("2d");

    const DOT_SPACING = 20, DOT_RADIUS = 1.5, BASE_OPACITY = 0.06;
    const RIPPLE_PEAK_OPACITY = 0.3, CYCLE_DURATION = 8000, RIPPLE_WIDTH = 150;
    const BLOOM_SIGMA = 140, BLOOM_DURATION = 3600, BLOOM_SPAWN_INTERVAL = 720;
    const BLOOM_BASE_ALPHA = 0.18, BLOOM_PEAK_ALPHA = 1;
    const FROWN_EYE_INFLUENCE = DOT_SPACING * 2.8, FROWN_MOUTH_INFLUENCE = DOT_SPACING * 1.7;
    const FROWN_PEAK = 0.9, FROWN_PERIOD = 3500;

    let width, height, cols, rows, maxDist;
    let frown = null;
    const ripples = [];
    const blooms = [];
    let lastBloomSpawn = -Infinity;
    let konamiMode = false;
    const KONAMI_SEQUENCE = ["ArrowUp","ArrowUp","ArrowDown","ArrowDown","ArrowLeft","ArrowRight","ArrowLeft","ArrowRight","b","a"];
    let konamiProgress = 0;

    // Frown mode is on whenever a [data-frown] marker is in the DOM (the 404
    // page). The canvas lives outside #main and persists across Swup swaps, so
    // this is re-evaluated on resize and after every Swup navigation — otherwise
    // the frown would stick around after you leave the 404.
    const updateFrown = () => {
      frown = document.querySelector("[data-frown]") ? frownPoints(width, height) : null;
    };

    const resize = () => {
      width = canvas.width = window.innerWidth;
      height = canvas.height = window.innerHeight;
      cols = Math.ceil(width / DOT_SPACING) + 1;
      rows = Math.ceil(height / DOT_SPACING) + 1;
      maxDist = Math.sqrt(width * width + height * height);
      updateFrown();
    };
    // Extra opacity for dots near the frown's features. `amp` (0..1) is the
    // breathing amplitude; the boost is a gaussian falloff from the nearest eye
    // or mouth point. Monochrome — drawn in the dot colour by the caller.
    const featureBoost = (x, y, points, influence) => {
      let nearestSq = Infinity;
      for (const p of points) {
        const dx = x - p.x, dy = y - p.y, dSq = dx * dx + dy * dy;
        if (dSq < nearestSq) nearestSq = dSq;
      }
      if (nearestSq > influence * influence) return 0;
      const sigma = influence / 2;
      return Math.exp(-nearestSq / (2 * sigma * sigma));
    };
    const frownBoost = (x, y, amp) => {
      if (!frown) return 0;
      const eye = featureBoost(x, y, frown.eyes, FROWN_EYE_INFLUENCE);
      const mouth = featureBoost(x, y, frown.mouth, FROWN_MOUTH_INFLUENCE);
      return amp * Math.max(eye, mouth);
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
        const frownAmp = 0.7 + 0.3 * Math.sin((timestamp / FROWN_PERIOD) * 2 * Math.PI);
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
            const finalOpacity = Math.min(1, opacity + FROWN_PEAK * frownBoost(x, y, frownAmp));
            ctx.beginPath();
            ctx.arc(x, y, DOT_RADIUS, 0, Math.PI * 2);
            ctx.fillStyle = `rgba(${dot}, ${finalOpacity})`;
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
          const x = col * DOT_SPACING, y = row * DOT_SPACING;
          const opacity = Math.min(1, baseOpacity + FROWN_PEAK * frownBoost(x, y, 1));
          ctx.beginPath();
          ctx.arc(x, y, DOT_RADIUS, 0, Math.PI * 2);
          ctx.fillStyle = `rgba(${dot}, ${opacity})`;
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
    // After a Swup page swap the canvas isn't re-mounted, so re-check whether the
    // new page is a 404 (the [data-frown] marker rides inside #main). The
    // animation loop reads `frown` each frame; the static render needs a repaint.
    this._onSwupContent = () => {
      updateFrown();
      if (reduceMotion.matches) renderStatic();
    };

    window.addEventListener("resize", this._onResize);
    window.addEventListener("keydown", this._onKonami);
    document.addEventListener("swup:content:replace", this._onSwupContent);
    reduceMotion.addEventListener("change", this._onMotionChange);
    resize();
    applyMotionPreference();
  },

  destroyed() {
    cancelAnimationFrame(this._raf);
    window.removeEventListener("resize", this._onResize);
    window.removeEventListener("keydown", this._onKonami);
    document.removeEventListener("swup:content:replace", this._onSwupContent);
    this._reduceMotion.removeEventListener("change", this._onMotionChange);
  },
};
