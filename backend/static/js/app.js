(function () {
  const toggle = document.getElementById('navToggle');
  const nav = document.getElementById('siteNav');
  if (toggle && nav) {
    toggle.addEventListener('click', function () {
      const open = nav.classList.toggle('is-open');
      toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
    });
    nav.querySelectorAll('a').forEach(function (link) {
      link.addEventListener('click', function () {
        if (window.matchMedia('(max-width: 899px)').matches) {
          nav.classList.remove('is-open');
          toggle.setAttribute('aria-expanded', 'false');
        }
      });
    });
  }

  // Mark active nav link
  if (nav) {
    const path = window.location.pathname.replace(/\/$/, '') || '/';
    nav.querySelectorAll('a[href]').forEach(function (a) {
      try {
        const href = new URL(a.href, window.location.origin).pathname.replace(/\/$/, '') || '/';
        if (href === path) a.classList.add('is-active');
      } catch (_) {}
    });
  }
})();
