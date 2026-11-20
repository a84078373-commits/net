(function () {
  const toggle = document.getElementById('navToggle');
  const nav = document.getElementById('siteNav');
  const backdrop = document.getElementById('sidebarBackdrop');

  function setOpen(open) {
    if (!nav) return;
    nav.classList.toggle('is-open', open);
    document.body.classList.toggle('sidebar-open', open);
    if (toggle) toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
    if (backdrop) backdrop.hidden = !open;
  }

  if (toggle && nav) {
    toggle.addEventListener('click', function () {
      setOpen(!nav.classList.contains('is-open'));
    });
    if (backdrop) {
      backdrop.addEventListener('click', function () { setOpen(false); });
    }
    nav.querySelectorAll('a').forEach(function (link) {
      link.addEventListener('click', function () {
        if (window.matchMedia('(max-width: 999px)').matches) setOpen(false);
      });
    });
  }

  if (nav) {
    const path = window.location.pathname.replace(/\/$/, '') || '/';
    const hash = window.location.hash || '';
    nav.querySelectorAll('a[data-nav]').forEach(function (a) {
      const target = a.getAttribute('data-nav') || '';
      const targetPath = target.split('#')[0] || '/';
      const targetHash = target.includes('#') ? '#' + target.split('#')[1] : '';
      if (targetPath === path && (!targetHash || targetHash === hash)) {
        a.classList.add('is-active');
      } else if (targetPath === path && !targetHash && !hash) {
        a.classList.add('is-active');
      }
    });
  }
})();
