document.addEventListener('DOMContentLoaded', function () {
  var path = window.location.pathname;
  var link = document.querySelector('#main-nav a[href="' + path + '"]');
  if (link) {
    link.setAttribute('aria-current', 'page');
  }
});
