// 404 page: show one of the headline and lead pairs at random. ?headline=1..4 forces one (used for screenshots), and
// automated browsers (navigator.webdriver) always get the first so page captures stay repeatable.
(function () {
  var lines = document.querySelectorAll('[data-line]');
  if (!lines.length) return;
  var forced = parseInt(new URLSearchParams(window.location.search).get('headline'), 10);
  var index = forced >= 1 && forced <= lines.length ? forced - 1
    : navigator.webdriver ? 0
    : Math.floor(Math.random() * lines.length);
  lines.forEach(function (line, i) { line.hidden = i !== index; });
})();
