/* Loaded only by browsers without ES modules (nomodule): too old for Pounce. On the TV page, say
   what to use instead. Served from /play/assets/, cached for good: change the file's number to
   change it. ES5 only. */
(function () {
  if (!/^\/play\/tv\/?$/.test(location.pathname)) return;
  var app = document.getElementById("app");
  if (!app) return;
  app.innerHTML = '<p class="noscript" style="font-size:5vh">Use a laptop or an Apple TV.</p>';
})();
