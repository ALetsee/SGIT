
document.addEventListener('click', function (e) {
  var p = e.target.closest('[data-print]');
  if (p) window.print();
});
document.addEventListener('submit', function (e) {
  var msg = e.target.getAttribute('data-confirm');
  if (msg && !window.confirm(msg)) e.preventDefault();
});

(function () {
  var sel = document.getElementById('vehiculo_id');
  if (!sel) return;
  var comb = document.querySelector('[data-nivel="comb"]');
  var carga = document.querySelector('[data-nivel="carga"]');
  if (!comb || !carga) return;
  var inComb = comb.querySelector('input'), inCarga = carga.querySelector('input');
  function ajustar() {
    var tipo = (sel.options[sel.selectedIndex] || {}).getAttribute ? sel.options[sel.selectedIndex].getAttribute('data-tipo') : '';
    var verComb = tipo !== 'EV', verCarga = tipo === 'EV' || tipo === 'PHEV' || tipo === 'HEV';
    comb.hidden = !verComb && !!tipo; carga.hidden = !verCarga && !!tipo;
    inComb.required = tipo === 'COMBUSTION' || tipo === 'PHEV' || tipo === 'HEV';
    inCarga.required = tipo === 'EV' || tipo === 'PHEV';
    if (comb.hidden) inComb.value = ''; if (carga.hidden) inCarga.value = '';
  }
  sel.addEventListener('change', ajustar); ajustar();
})();

(function () {
  var sel = document.getElementById('concepto');
  if (!sel) return;
  var lc = document.getElementById('lbl-pcant'), lk = document.getElementById('lbl-pcosto');
  function ajustar() {
    var o = sel.options[sel.selectedIndex];
    if (!o) return;
    if (lc) lc.textContent = o.getAttribute('data-cant') || 'Cantidad';
    if (lk) lk.textContent = o.getAttribute('data-costo') || 'Costo unitario (sin margen ni IVA)';
  }
  sel.addEventListener('change', ajustar); ajustar();
})();

if ('serviceWorker' in navigator) {
  window.addEventListener('load', function () {
    navigator.serviceWorker.register('/sw.js').catch(function () {});
  });
}
