// Turns on Bootstrap tooltips (social icons). Runs after the deferred Bootstrap bundle; links keep their aria-label.
document.addEventListener('DOMContentLoaded', function () {
  if (!window.bootstrap) return;
  document.querySelectorAll('[data-bs-toggle="tooltip"]').forEach(function (el) {
    new window.bootstrap.Tooltip(el);
  });
});
