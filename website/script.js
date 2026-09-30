(() => {
  "use strict";

  /* ---------- mobile nav ---------- */

  const navToggle = document.getElementById("navToggle");
  const mobileNav = document.getElementById("mobileNav");
  if (navToggle && mobileNav) {
    navToggle.addEventListener("click", () => {
      const open = mobileNav.classList.toggle("is-open");
      navToggle.setAttribute("aria-expanded", String(open));
      navToggle.setAttribute("aria-label", open ? "Close menu" : "Open menu");
    });
    mobileNav.querySelectorAll("a").forEach((a) =>
      a.addEventListener("click", () => {
        mobileNav.classList.remove("is-open");
        navToggle.setAttribute("aria-expanded", "false");
      })
    );
  }

  /* ---------- exploded hero parallax ---------- */
  /* Each [data-depth] layer drifts at its own rate on scroll, and tilts
     gently toward the pointer - the "exploded" pieces read as separate
     depths rather than a flat collage. Skipped entirely under
     prefers-reduced-motion. */

  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const heroVisual = document.getElementById("heroVisual");

  if (heroVisual && !reduceMotion) {
    const layers = Array.from(heroVisual.querySelectorAll("[data-depth]")).map((el) => ({
      el,
      depth: parseFloat(el.dataset.depth) || 0.3,
    }));

    let scrollOffset = 0;
    let pointer = { x: 0, y: 0 }; // -1..1
    let ticking = false;

    const apply = () => {
      const rect = heroVisual.getBoundingClientRect();
      const inView = rect.bottom > 0 && rect.top < window.innerHeight;
      if (inView) {
        for (const layer of layers) {
          const scrollShift = scrollOffset * layer.depth * 40;
          const px = pointer.x * layer.depth * 14;
          const py = pointer.y * layer.depth * 14;
          layer.el.style.transform =
            `translate3d(${px}px, ${scrollShift + py}px, 0)`;
        }
      }
      ticking = false;
    };

    const requestTick = () => {
      if (!ticking) {
        ticking = true;
        requestAnimationFrame(apply);
      }
    };

    const onScroll = () => {
      const rect = heroVisual.getBoundingClientRect();
      // -1 (scrolled well past) .. 1 (below viewport) - 0 while centered.
      scrollOffset = (window.innerHeight / 2 - (rect.top + rect.height / 2)) / window.innerHeight;
      requestTick();
    };

    const onPointerMove = (e) => {
      const rect = heroVisual.getBoundingClientRect();
      pointer.x = ((e.clientX - rect.left) / rect.width) * 2 - 1;
      pointer.y = ((e.clientY - rect.top) / rect.height) * 2 - 1;
      requestTick();
    };

    const onPointerLeave = () => {
      pointer = { x: 0, y: 0 };
      requestTick();
    };

    window.addEventListener("scroll", onScroll, { passive: true });
    heroVisual.addEventListener("pointermove", onPointerMove);
    heroVisual.addEventListener("pointerleave", onPointerLeave);
    onScroll();
  }

  /* ---------- accent color demo ---------- */

  const accentDemo = document.getElementById("accentDemo");
  if (accentDemo) {
    const buttons = accentDemo.querySelectorAll(".swatch-btn");
    buttons.forEach((btn) => {
      btn.addEventListener("click", () => {
        buttons.forEach((b) => b.classList.remove("is-active"));
        btn.classList.add("is-active");
        const color = btn.dataset.accent;
        accentDemo.style.setProperty("--demo-accent", color);
      });
    });
  }

  /* ---------- bottom bar style demo ---------- */

  const barDemo = document.getElementById("barDemo");
  const demoBar = document.getElementById("demoBar");
  if (barDemo && demoBar) {
    const buttons = barDemo.querySelectorAll(".segmented-btn");
    buttons.forEach((btn) => {
      btn.addEventListener("click", () => {
        buttons.forEach((b) => b.classList.remove("is-active"));
        btn.classList.add("is-active");
        demoBar.classList.toggle("is-attached", btn.dataset.bar === "attached");
      });
    });
  }

  /* ---------- scroll reveal ---------- */

  const revealTargets = document.querySelectorAll(
    ".card, .customize-demo, .customize-list, .privacy-points li"
  );
  revealTargets.forEach((el) => el.classList.add("reveal"));

  if ("IntersectionObserver" in window && !reduceMotion) {
    const io = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            entry.target.classList.add("is-visible");
            io.unobserve(entry.target);
          }
        }
      },
      { threshold: 0.15, rootMargin: "0px 0px -40px 0px" }
    );
    revealTargets.forEach((el) => io.observe(el));
  } else {
    revealTargets.forEach((el) => el.classList.add("is-visible"));
  }
})();
