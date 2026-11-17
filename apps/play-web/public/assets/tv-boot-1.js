/* The TV page's check that the app started. Older smart-TV browsers (Tizen and webOS, Chromium about
   63 to 79) load modules but can't parse the app's, so `nomodule` never fires and the screen stays
   blank. main.tsx sets window.__pounceBooted as it runs; if a module fails to parse, or the page
   has loaded and the app still hasn't started, say what to use instead. A classic script, not
   inline (the CSP allows only 'self'). Served from /play/assets/, cached for good: change the
   file's number to change it. ES5 only. */
(function () {
  if (!/^\/play\/tv\/?$/.test(location.pathname)) return;
  var shown = false;
  function show() {
    if (shown || window.__pounceBooted) return;
    shown = true;
    var app = document.getElementById("app");
    if (app) app.innerHTML = '<p class="noscript" style="font-size:5vh">Use a laptop or an Apple TV.</p>';
  }
  window.addEventListener("error", function (e) {
    var name = e && e.error && e.error.name;
    if (name === "SyntaxError" || /SyntaxError/.test((e && e.message) || "")) show();
  });
  window.addEventListener("load", function () {
    setTimeout(show, 3000);
  });
})();
