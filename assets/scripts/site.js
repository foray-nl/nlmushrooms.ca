// Turns on Bootstrap tooltips (social icons). Runs after the deferred Bootstrap bundle; links keep their aria-label.
document.addEventListener('DOMContentLoaded', function () {
  if (!window.bootstrap) return;
  document.querySelectorAll('[data-bs-toggle="tooltip"]').forEach(function (el) {
    new window.bootstrap.Tooltip(el);
  });
});

// Footer: show the "Next foray" line only while that foray is ongoing or still ahead. ?today=YYYY-MM-DD sets the date
// being compared (used to capture repeatable screenshots); the line stays hidden without JavaScript.
document.addEventListener('DOMContentLoaded', function () {
  var line = document.querySelector('.footer-next-foray');
  if (!line) return;
  var override = new URLSearchParams(window.location.search).get('today');
  var now = new Date();
  var today = /^\d{4}-\d{2}-\d{2}$/.test(override || '') ? override
    : now.getFullYear() + '-' + String(now.getMonth() + 1).padStart(2, '0') + '-' + String(now.getDate()).padStart(2, '0');
  if (line.dataset.end >= today) line.hidden = false;
});
