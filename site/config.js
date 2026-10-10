/* ==========================================================================
   CONFIGURAÇÕES DO SITE DO MAPLONG
   É só este arquivo que você precisa editar. Troque o que está entre as
   aspas ('...'), salve e publique o site de novo.
   Passo a passo completo: docs/SITE_DE_VENDAS.md
   ========================================================================== */

window.MAPLONG = {
  /* 1) LINK DE PAGAMENTO -------------------------------------------------
     Cole aqui o link do checkout do seu produto. Exemplos:
       Kiwify:  'https://pay.kiwify.com.br/AbCdEfG'
       Cakto:   'https://pay.cakto.com.br/abc123_456789'
       Kirvano: 'https://pay.kirvano.com/00000000-0000-0000-0000-000000000000'
     Todos os botões "Comprar" do site passam a abrir esse link.            */
  linkPagamento: '',

  /* 2) PREÇO mostrado no site ------------------------------------------- */
  preco: 'R$ 69,00',
  precoAntigo: '', //            ex.: 'R$ 97,00' (aparece riscado). Vazio = não mostra.
  parcelamento: '', //           ex.: 'ou em até 12x no cartão'

  /* 3) DOWNLOAD (página download.html, entregue depois da compra) --------
     Link do instalador do MapLong (GitHub, Google Drive, Dropbox…).        */
  linkDownloadWindows: '',

  /* 4) CONTATO (rodapé, dúvidas e página de download) -------------------- */
  emailSuporte: '', //           ex.: 'contato@seudominio.com.br'
  whatsapp: '', //               só números, com 55 e DDD. ex.: '5511999999999'

  /* 5) GARANTIA em dias (as plataformas pedem no mínimo 7) --------------- */
  diasGarantia: 7,

  /* 6) VERSÃO WEB (opcional): link para usar no navegador. Vazio = oculto. */
  linkVersaoWeb: '',
};
