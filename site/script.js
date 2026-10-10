/* Aplica as configurações de config.js nas páginas do site. Não precisa
   editar este arquivo: as alterações são feitas em config.js. */
(function () {
  'use strict';

  var c = window.MAPLONG || {};
  var texto = function (v) {
    return typeof v === 'string' ? v.trim() : '';
  };
  var todos = function (sel) {
    return Array.prototype.slice.call(document.querySelectorAll(sel));
  };

  var linkPagamento = texto(c.linkPagamento);
  var local =
    location.protocol === 'file:' ||
    location.hostname === 'localhost' ||
    location.hostname === '127.0.0.1';

  // Repassa ao checkout os parâmetros de campanha (utm_*, src, sck) com que o
  // visitante chegou ao site, para a plataforma mostrar de onde veio a venda.
  function comCampanha(url) {
    try {
      var destino = new URL(url);
      new URLSearchParams(location.search).forEach(function (valor, chave) {
        if (/^(utm_|src$|sck$)/.test(chave) && !destino.searchParams.has(chave)) {
          destino.searchParams.set(chave, valor);
        }
      });
      return destino.toString();
    } catch (e) {
      return url;
    }
  }

  // Botões "Comprar" (sem link configurado, continuam levando à seção Preço).
  if (linkPagamento) {
    todos('[data-comprar]').forEach(function (botao) {
      botao.href = comCampanha(linkPagamento);
    });
  }
  if (!linkPagamento && local) {
    todos('.aviso-config').forEach(function (el) {
      el.hidden = false;
    });
  }

  // Preço, preço antigo, parcelamento e garantia.
  var preco = texto(c.preco);
  if (preco) {
    todos('[data-preco]').forEach(function (el) {
      el.textContent = preco;
    });
  }
  var antigo = texto(c.precoAntigo);
  todos('[data-preco-antigo]').forEach(function (el) {
    el.textContent = antigo;
    el.hidden = !antigo;
  });
  var parcelas = texto(c.parcelamento);
  todos('[data-parcelamento]').forEach(function (el) {
    el.textContent = parcelas;
    el.hidden = !parcelas;
  });
  var dias = parseInt(c.diasGarantia, 10);
  if (dias > 0) {
    todos('[data-garantia]').forEach(function (el) {
      el.textContent = String(dias);
    });
  }

  // Contato.
  var email = texto(c.emailSuporte);
  todos('[data-email]').forEach(function (el) {
    if (!email) return;
    el.href = 'mailto:' + email;
    if (el.hasAttribute('data-mostrar-endereco')) el.textContent = email;
    el.hidden = false;
  });
  var whats = texto(c.whatsapp).replace(/\D/g, '');
  todos('[data-whatsapp]').forEach(function (el) {
    if (!whats) return;
    el.href =
      'https://wa.me/' + whats + '?text=' + encodeURIComponent('Olá! Tenho uma dúvida sobre o MapLong.');
    el.hidden = false;
  });
  todos('[data-sem-contato]').forEach(function (el) {
    el.hidden = Boolean(email || whats);
  });

  // Versão para navegador (opcional).
  var web = texto(c.linkVersaoWeb);
  todos('[data-versao-web]').forEach(function (el) {
    if (!web) return;
    el.href = web;
    el.hidden = false;
  });

  // Download (página download.html).
  var download = texto(c.linkDownloadWindows);
  todos('[data-download]').forEach(function (el) {
    if (download) {
      el.href = download;
      el.hidden = false;
    } else {
      el.hidden = true;
    }
  });
  todos('[data-sem-download]').forEach(function (el) {
    el.hidden = Boolean(download);
  });

  // Ano do rodapé.
  todos('[data-ano]').forEach(function (el) {
    el.textContent = String(new Date().getFullYear());
  });
})();
