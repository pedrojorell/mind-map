// Servidor de vendas do MapLong (Cloudflare Workers).
//
//   GET  /                      página de compra
//   GET  /comprar               cria o pagamento no Mercado Pago e redireciona
//   GET  /obrigado              volta do Mercado Pago: mostra o código da licença
//   POST /webhook/mercadopago   aviso de pagamento: envia o código por e-mail
//   GET  /admin                 gerador on-line (protegido por senha)
//   GET  /saude                 mostra o que já está configurado
//
// Segredos (npx wrangler secret put NOME):
//   MP_ACCESS_TOKEN      token de produção do Mercado Pago
//   LICENSE_PRIVATE_KEY  chave privada (linha do arquivo segredos-do-servidor.txt)
//   ADMIN_PASSWORD       senha da página /admin
//   BREVO_API_KEY        (opcional) envio do código por e-mail
//   MP_WEBHOOK_SECRET    (opcional) confere a assinatura dos avisos do Mercado Pago
// Variáveis em wrangler.toml: PRICE, PRODUCT_NAME, EMAIL_FROM, EMAIL_FROM_NAME,
// DOWNLOAD_URL. Banco opcional (KV) LICENCAS: registra as licenças emitidas.

import {
  ErroLicenca,
  PLANOS,
  assinarLicenca,
  dataIso,
  emailValido,
  importarChavePrivada,
  normalizarEmail,
} from './licenca.js';

const MP_API = 'https://api.mercadopago.com';
const BREVO_API = 'https://api.brevo.com/v3/smtp/email';

export default {
  async fetch(request, env) {
    try {
      return await rotear(request, env);
    } catch (e) {
      if (e instanceof ErroConfig) {
        return pagina('Loja em configuração', `<p>${esc(e.message)}</p>`, 503);
      }
      console.error('MapLong:', e);
      return pagina(
        'Algo deu errado',
        '<p>Não foi possível concluir agora. Tente de novo em alguns instantes.</p>',
        500,
      );
    }
  },
};

async function rotear(request, env) {
  const url = new URL(request.url);
  const caminho = url.pathname.replace(/\/+$/, '') || '/';
  const get = request.method === 'GET' || request.method === 'HEAD';
  if (get && caminho === '/') return inicio(env);
  if (get && caminho === '/comprar') return comprar(url, env);
  if (get && caminho === '/obrigado') return obrigado(url, env);
  if (request.method === 'POST' && caminho === '/webhook/mercadopago') {
    return webhook(request, url, env);
  }
  if (caminho === '/admin') {
    return request.method === 'POST' ? adminGerar(request, env) : adminFormulario(env);
  }
  if (get && caminho === '/saude') return saude(env);
  return pagina('Página não encontrada', '<p><a href="/">Voltar ao início</a></p>', 404);
}

// ------------------------------------------------------------ configuração

class ErroConfig extends Error {}

function exigir(env, nomes) {
  const faltando = nomes.filter((n) => !env[n]);
  if (faltando.length) {
    throw new ErroConfig(`Falta configurar no servidor: ${faltando.join(', ')}.`);
  }
}

export function preco(env) {
  const n = Number(String(env.PRICE ?? '69.00').replace(',', '.'));
  return Number.isFinite(n) && n > 0 ? Math.round(n * 100) / 100 : 69;
}

function precoTexto(env) {
  return `R$ ${preco(env).toFixed(2).replace('.', ',')}`;
}

const produto = (env) => env.PRODUCT_NAME || 'MapLong';

function aleatorio(bytes = 16) {
  const b = crypto.getRandomValues(new Uint8Array(bytes));
  return [...b].map((x) => x.toString(16).padStart(2, '0')).join('');
}

// ------------------------------------------------------------ Mercado Pago

async function mp(env, caminho, init = {}) {
  const r = await fetch(`${MP_API}${caminho}`, {
    ...init,
    headers: {
      authorization: `Bearer ${env.MP_ACCESS_TOKEN}`,
      'content-type': 'application/json',
      ...(init.headers ?? {}),
    },
  });
  if (r.status === 404) return null;
  if (!r.ok) throw new Error(`Mercado Pago respondeu ${r.status}: ${await r.text()}`);
  return r.json();
}

/** Pagamento consultado direto no Mercado Pago (fonte confiável). */
async function buscarPagamento(env, id) {
  exigir(env, ['MP_ACCESS_TOKEN']);
  return mp(env, `/v1/payments/${encodeURIComponent(id)}`);
}

/** É um pagamento aprovado desta loja, no valor certo? */
export function pagamentoValido(p, env) {
  return (
    p?.status === 'approved' &&
    p.currency_id === 'BRL' &&
    Number(p.transaction_amount) + 0.001 >= preco(env) &&
    String(p.external_reference ?? '').startsWith('ML-')
  );
}

/** O mesmo pagamento gera sempre o mesmo código. */
async function licencaDoPagamento(p, env) {
  exigir(env, ['LICENSE_PRIVATE_KEY']);
  let email = normalizarEmail(p.payer?.email);
  if (!emailValido(email)) email = `cliente-${p.id}@pagamento.invalid`;
  const chave = await importarChavePrivada(env.LICENSE_PRIVATE_KEY);
  const codigo = await assinarLicenca(chave, {
    id: `MP-${p.id}`,
    email,
    plano: 'pro',
    data: dataIso(p.date_approved ?? p.date_created ?? Date.now()),
  });
  return { codigo, email };
}

async function comprar(url, env) {
  exigir(env, ['MP_ACCESS_TOKEN', 'LICENSE_PRIVATE_KEY']);
  const origem = url.origin;
  const email = normalizarEmail(url.searchParams.get('email'));
  const preferencia = await mp(env, '/checkout/preferences', {
    method: 'POST',
    body: JSON.stringify({
      items: [
        {
          id: 'maplong-pro',
          title: `${produto(env)} - licença vitalícia`,
          description: 'Acesso completo ao MapLong, sem mensalidade.',
          quantity: 1,
          currency_id: 'BRL',
          unit_price: preco(env),
        },
      ],
      // Referência secreta: só quem fez a compra consegue ver o código depois.
      external_reference: `ML-${aleatorio()}`,
      back_urls: {
        success: `${origem}/obrigado`,
        pending: `${origem}/obrigado`,
        failure: `${origem}/`,
      },
      auto_return: 'approved',
      notification_url: `${origem}/webhook/mercadopago`,
      statement_descriptor: 'MAPLONG',
      ...(emailValido(email) ? { payer: { email } } : {}),
    }),
  });
  const destino = preferencia?.init_point;
  if (!destino) throw new Error('Mercado Pago não retornou o link de pagamento');
  return Response.redirect(destino, 303);
}

async function obrigado(url, env) {
  const id = url.searchParams.get('payment_id') ?? url.searchParams.get('collection_id');
  const ref = url.searchParams.get('external_reference');
  const naoEncontrado = () =>
    pagina(
      'Pagamento não encontrado',
      '<p>Não encontramos esta compra. Se você já pagou, o código também é ' +
        'enviado para o seu e-mail.</p><p><a href="/">Voltar ao início</a></p>',
      404,
    );
  if (!id || !/^\d+$/.test(id) || !ref) return naoEncontrado();
  const p = await buscarPagamento(env, id);
  if (!p || p.external_reference !== ref) return naoEncontrado();

  if (p.status === 'approved') {
    if (!pagamentoValido(p, env)) {
      return pagina(
        'Pagamento não reconhecido',
        '<p>O valor deste pagamento não corresponde à licença do MapLong. ' +
          'Entre em contato para resolvermos.</p>',
      );
    }
    const { codigo, email } = await licencaDoPagamento(p, env);
    return pagina('Pagamento aprovado!', paginaCodigo(env, codigo, email));
  }
  if (['pending', 'in_process', 'authorized'].includes(p.status)) {
    return pagina(
      'Aguardando a confirmação',
      '<p>Estamos esperando o Mercado Pago confirmar o pagamento. No Pix isso ' +
        'leva só alguns segundos; esta página se atualiza sozinha.</p>' +
        '<p class="fraco">Você também vai receber o código por e-mail.</p>',
      200,
      '<meta http-equiv="refresh" content="8">',
    );
  }
  return pagina(
    'Pagamento não aprovado',
    '<p>O pagamento não foi concluído. Nenhum valor foi cobrado.</p>' +
      '<p><a class="botao" href="/comprar">Tentar de novo</a></p>',
  );
}

/** Confere a assinatura x-signature do Mercado Pago (quando ela vem). */
async function assinaturaValida(request, url, segredo) {
  const cabecalho = request.headers.get('x-signature');
  if (!cabecalho) return true; // avisos no formato antigo não são assinados
  const partes = Object.fromEntries(
    cabecalho.split(',').map((p) => p.trim().split('=').map((s) => s.trim())),
  );
  if (!partes.ts || !partes.v1) return false;
  let dataId = url.searchParams.get('data.id') ?? '';
  if (/[a-z]/i.test(dataId)) dataId = dataId.toLowerCase();
  const pedido = request.headers.get('x-request-id');
  let manifesto = '';
  if (dataId) manifesto += `id:${dataId};`;
  if (pedido) manifesto += `request-id:${pedido};`;
  manifesto += `ts:${partes.ts};`;
  const chave = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(segredo),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const mac = new Uint8Array(
    await crypto.subtle.sign('HMAC', chave, new TextEncoder().encode(manifesto)),
  );
  const hex = [...mac].map((x) => x.toString(16).padStart(2, '0')).join('');
  return iguais(hex, partes.v1.toLowerCase());
}

async function webhook(request, url, env) {
  if (env.MP_WEBHOOK_SECRET && !(await assinaturaValida(request, url, env.MP_WEBHOOK_SECRET))) {
    return new Response('assinatura inválida', { status: 401 });
  }
  const corpo = await request.json().catch(() => ({}));
  const tipo = corpo?.type ?? url.searchParams.get('type') ?? url.searchParams.get('topic');
  const id = String(corpo?.data?.id ?? url.searchParams.get('data.id') ?? url.searchParams.get('id') ?? '');
  if (tipo !== 'payment' || !/^\d+$/.test(id)) return new Response('ignorado');

  const p = await buscarPagamento(env, id);
  if (!pagamentoValido(p, env)) return new Response('ok');
  const { codigo, email } = await licencaDoPagamento(p, env);
  await registrarEEnviar(env, `MP-${p.id}`, email, codigo);
  return new Response('ok');
}

// ------------------------------------------------------------------ e-mail

/** Envia o código uma única vez (com o KV) e guarda o registro da venda. */
async function registrarEEnviar(env, id, email, codigo, { forcar = false } = {}) {
  const chaveKv = `licenca:${id}`;
  if (!forcar && env.LICENCAS && (await env.LICENCAS.get(chaveKv))) return false;
  const enviado = await enviarEmail(env, email, codigo);
  if (env.LICENCAS) {
    await env.LICENCAS.put(
      chaveKv,
      JSON.stringify({ email, codigo, enviado, quando: new Date().toISOString() }),
    );
  }
  return enviado;
}

function emailConfigurado(env) {
  return Boolean(env.BREVO_API_KEY && emailValido(normalizarEmail(env.EMAIL_FROM)));
}

async function enviarEmail(env, email, codigo) {
  if (!emailConfigurado(env) || email.endsWith('.invalid')) return false;
  const nome = produto(env);
  const r = await fetch(BREVO_API, {
    method: 'POST',
    headers: {
      'api-key': env.BREVO_API_KEY,
      'content-type': 'application/json',
      accept: 'application/json',
    },
    body: JSON.stringify({
      sender: { name: env.EMAIL_FROM_NAME || nome, email: env.EMAIL_FROM },
      to: [{ email }],
      subject: `Sua licença do ${nome}`,
      htmlContent: emailHtml(env, codigo),
      textContent: emailTexto(env, codigo),
    }),
  });
  // Erro aqui faz o Mercado Pago repetir o aviso mais tarde.
  if (!r.ok) throw new Error(`Brevo respondeu ${r.status}: ${await r.text()}`);
  return true;
}

function passos() {
  return [
    'Abra o MapLong.',
    'Clique em Configurações (ícone de engrenagem) e depois em "Ativar licença".',
    'Cole o código e clique em Ativar.',
  ];
}

function emailTexto(env, codigo) {
  return [
    `Obrigado por comprar o ${produto(env)}!`,
    '',
    'Seu código de licença:',
    codigo,
    '',
    ...passos().map((p, i) => `${i + 1}. ${p}`),
    '',
    env.DOWNLOAD_URL ? `Baixar o ${produto(env)}: ${env.DOWNLOAD_URL}` : '',
  ].join('\n');
}

function emailHtml(env, codigo) {
  return `<div style="font-family:Segoe UI,Arial,sans-serif;max-width:560px;color:#1d1b2e">
<h2 style="color:#4338ca">Obrigado por comprar o ${esc(produto(env))}!</h2>
<p>Seu código de licença:</p>
<p style="font-family:Consolas,monospace;font-size:13px;background:#f1f0fb;border-radius:8px;padding:12px;word-break:break-all">${esc(codigo)}</p>
<ol>${passos().map((p) => `<li>${esc(p)}</li>`).join('')}</ol>
${env.DOWNLOAD_URL ? `<p><a href="${esc(env.DOWNLOAD_URL)}">Baixar o ${esc(produto(env))}</a></p>` : ''}
<p style="color:#6b6880;font-size:12px">Guarde este e-mail: o código vale para sempre.</p>
</div>`;
}

// ------------------------------------------------------------------- admin

/** Comparação em tempo constante (evita adivinhar a senha pelo tempo). */
function iguais(a, b) {
  const x = new TextEncoder().encode(String(a));
  const y = new TextEncoder().encode(String(b));
  let dif = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) dif |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return dif === 0;
}

function formularioAdmin(env, erro = '') {
  return `${erro ? `<p class="erro">${esc(erro)}</p>` : ''}
<form method="post" class="form">
  <label>Senha do gerador<input type="password" name="senha" required autocomplete="current-password"></label>
  <label>E-mail do cliente<input type="email" name="email" placeholder="cliente@email.com"></label>
  <label>Plano<select name="plano"><option value="pro">Pro (cliente)</option><option value="dono">Proprietário</option></select></label>
  <label>Nº do pagamento no Mercado Pago (opcional: recupera o código de uma venda)<input name="pagamento" inputmode="numeric"></label>
  ${emailConfigurado(env) ? '<label class="linha"><input type="checkbox" name="enviar" value="1"> Enviar o código por e-mail</label>' : ''}
  <button class="botao" type="submit">Gerar licença</button>
</form>`;
}

function adminFormulario(env) {
  if (!env.ADMIN_PASSWORD) {
    return pagina('Gerador desativado', '<p>Configure o segredo ADMIN_PASSWORD.</p>', 503);
  }
  return pagina('Gerador de licenças', formularioAdmin(env));
}

async function adminGerar(request, env) {
  if (!env.ADMIN_PASSWORD) return adminFormulario(env);
  const f = await request.formData();
  if (!iguais(f.get('senha') ?? '', env.ADMIN_PASSWORD)) {
    return pagina('Gerador de licenças', formularioAdmin(env, 'Senha incorreta.'), 401);
  }
  exigir(env, ['LICENSE_PRIVATE_KEY']);
  try {
    let codigo, email;
    let id = '';
    const pagamento = String(f.get('pagamento') ?? '').trim();
    if (pagamento) {
      const p = /^\d+$/.test(pagamento) ? await buscarPagamento(env, pagamento) : null;
      if (!pagamentoValido(p, env)) throw new ErroLicenca('Pagamento não encontrado ou não aprovado.');
      ({ codigo, email } = await licencaDoPagamento(p, env));
      id = `MP-${p.id}`;
    } else {
      const plano = PLANOS.includes(f.get('plano')) ? f.get('plano') : 'pro';
      email = normalizarEmail(f.get('email'));
      id = `${plano === 'dono' ? 'DONO' : 'ADM'}-${aleatorio(5).toUpperCase()}`;
      const chave = await importarChavePrivada(env.LICENSE_PRIVATE_KEY);
      codigo = await assinarLicenca(chave, { id, email, plano });
    }
    let aviso = '';
    if (f.get('enviar')) {
      const ok = await registrarEEnviar(env, id, email, codigo, { forcar: true });
      aviso = ok ? `<p class="ok">Enviado para ${esc(email)}.</p>` : '<p class="erro">Não foi possível enviar o e-mail.</p>';
    } else if (env.LICENCAS) {
      await env.LICENCAS.put(`licenca:${id}`, JSON.stringify({ email, codigo, enviado: false, quando: new Date().toISOString() }));
    }
    return pagina('Licença gerada', `${aviso}${paginaCodigo(env, codigo, email)}<p><a href="/admin">Gerar outra</a></p>`);
  } catch (e) {
    if (!(e instanceof ErroLicenca)) throw e;
    return pagina('Gerador de licenças', formularioAdmin(env, e.message), 400);
  }
}

function saude(env) {
  return Response.json({
    ok: true,
    preco: preco(env),
    mercadoPago: Boolean(env.MP_ACCESS_TOKEN),
    chaveDeLicenca: Boolean(env.LICENSE_PRIVATE_KEY),
    gerador: Boolean(env.ADMIN_PASSWORD),
    email: emailConfigurado(env),
    conferenciaDeAssinatura: Boolean(env.MP_WEBHOOK_SECRET),
    registroKv: Boolean(env.LICENCAS),
  });
}

// ------------------------------------------------------------------ páginas

export function esc(s) {
  return String(s ?? '').replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
}

function paginaCodigo(env, codigo, email) {
  return `<p>Licença de <strong>${esc(email)}</strong>. Copie o código abaixo:</p>
<pre id="codigo" class="codigo">${esc(codigo)}</pre>
<p><button class="botao" type="button" onclick="navigator.clipboard.writeText(document.getElementById('codigo').textContent).then(()=>{this.textContent='Copiado!'})">Copiar código</button></p>
<ol>${passos().map((p) => `<li>${esc(p)}</li>`).join('')}</ol>
${env.DOWNLOAD_URL ? `<p>Ainda não tem o app? <a href="${esc(env.DOWNLOAD_URL)}">Baixe o ${esc(produto(env))}</a>.</p>` : ''}`;
}

function inicio(env) {
  return pagina(
    `${produto(env)} — licença vitalícia`,
    `<p class="destaque">Mapas mentais completos, offline, com tudo liberado para sempre.</p>
<p class="preco">${precoTexto(env)} <span>pagamento único</span></p>
<form action="/comprar" method="get" class="form">
  <label>Seu e-mail (para receber o código)<input type="email" name="email" placeholder="voce@email.com"></label>
  <button class="botao" type="submit">Comprar com Mercado Pago</button>
</form>
<p class="fraco">Pix, cartão ou boleto. O código de ativação aparece logo após o pagamento e chega por e-mail.</p>
${env.DOWNLOAD_URL ? `<p><a href="${esc(env.DOWNLOAD_URL)}">Baixar o ${esc(produto(env))} (teste grátis)</a></p>` : ''}`,
  );
}

function pagina(titulo, corpo, status = 200, cabecaExtra = '') {
  const html = `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">${cabecaExtra}
<title>${esc(titulo)}</title><meta name="robots" content="noindex">
<style>
:root{--fundo:#f5f4fb;--cartao:#fff;--texto:#1d1b2e;--fraco:#6b6880;--marca:#4f46e5;--borda:#e3e1f0}
@media (prefers-color-scheme:dark){:root{--fundo:#121120;--cartao:#1c1a2e;--texto:#ecebf5;--fraco:#a3a0b8;--marca:#8b85ff;--borda:#2f2c47}}
*{box-sizing:border-box}body{margin:0;background:var(--fundo);color:var(--texto);font:16px/1.55 "Segoe UI",system-ui,sans-serif}
main{max-width:620px;margin:40px auto;padding:0 16px}.cartao{background:var(--cartao);border:1px solid var(--borda);border-radius:18px;padding:28px}
.marca{font-weight:800;font-size:22px;background:linear-gradient(90deg,#2563eb,#7c3aed);-webkit-background-clip:text;background-clip:text;color:transparent}
h1{font-size:24px;margin:8px 0 16px}a{color:var(--marca)}.fraco{color:var(--fraco);font-size:14px}
.botao{display:inline-block;border:0;border-radius:12px;padding:12px 20px;font-family:inherit;font-size:15px;font-weight:600;color:#fff;background:linear-gradient(90deg,#2563eb,#7c3aed);cursor:pointer;text-decoration:none}
.codigo{white-space:pre-wrap;word-break:break-all;font:13px Consolas,monospace;background:var(--fundo);border:1px solid var(--borda);border-radius:10px;padding:14px}
.form{display:grid;gap:14px;margin:18px 0}.form label{display:grid;gap:6px;font-size:14px;color:var(--fraco)}.form .linha{display:flex;align-items:center;gap:8px}
input,select{font:inherit;padding:10px 12px;border-radius:10px;border:1px solid var(--borda);background:var(--fundo);color:var(--texto)}
.preco{font-size:32px;font-weight:800;margin:12px 0}.preco span{font-size:14px;font-weight:400;color:var(--fraco)}
.destaque{font-size:18px}.erro{color:#dc2626;font-weight:600}.ok{color:#16a34a;font-weight:600}
</style></head><body><main><div class="cartao"><div class="marca">MapLong</div><h1>${esc(titulo)}</h1>${corpo}</div></main></body></html>`;
  return new Response(html, {
    status,
    headers: {
      'content-type': 'text/html; charset=utf-8',
      'cache-control': 'no-store',
      'x-frame-options': 'DENY',
      'referrer-policy': 'no-referrer',
    },
  });
}
