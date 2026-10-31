(function () {
  var CLAVE = 'sgit-tema';
  var raiz = document.documentElement;

  var guardado = null;
  try { guardado = localStorage.getItem(CLAVE); } catch (e) {}

  var oscuroSistema = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
  raiz.dataset.tema = guardado || (oscuroSistema ? 'oscuro' : 'claro');

  function guardar() {
    try { localStorage.setItem(CLAVE, raiz.dataset.tema); } catch (e) {}
  }

  document.addEventListener('DOMContentLoaded', function () {
    var botones = document.querySelectorAll('[data-cambiar-tema]');
    botones.forEach(function (b) {
      b.addEventListener('click', function () {
        raiz.dataset.tema = raiz.dataset.tema === 'oscuro' ? 'claro' : 'oscuro';
        guardar();
      });
    });
  });
})();
