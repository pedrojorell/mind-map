import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { afterEach, beforeEach, test } from 'node:test';

import { conferirLicenca, gerarChaves } from '../src/licenca.js';
import worker from '../src/worker.js';

const ORIGEM = 'https://loja.exemplo.workers.dev';
let chaves;
let env;
let chamadas;
let pagamentos;
const fetchOriginal = globalThis.fetch;

/** KV em memória, igual ao do Cloudflare. */
function kv() {
  const m = new Map();
  return { get: async (k) => m.get(k) ?? null, put: async (k, v) => void m.set(k, v), m };
}

beforeEach(async () => {
  chaves ??= await gerarChaves();
  env = {
    MP_ACCESS_TOKEN: 'APP_USR-teste',
    LICENSE_PRIVATE_KEY: JSON.stringify(chaves.privada),
    ADMIN_PASSWORD: 'senha-forte-de-teste',
    BREVO_API_KEY: 'xkeysib-teste',
    EMAIL_FROM: 'vendas@exemplo.com',
    PRICE: '69.00',
    DOWNLOAD_URL: 'https://exemplo.com/baixar',
  };
  chamadas = [];
  pagamentos = new Map();
  globalThis.fetch = async (url, init = {}) => {
    const u = String(url);
    const corpo = init.body ? JSON.parse(init.body) : undefined;
    chamadas.push({ url: u, metodo: init.method ?? 'GET', corpo, headers: init.headers });
    if (u === 'https://api.mercadopago.com/checkout/preferences') {
      return Response.json({ id: 'pref-1', init_point: 'https://www.mercadopago.com.br/checkout/v1/redirect?pref_id=pref-1' }, { status: 201 });
    }
    const m = u.match(/^https:\/\/api\.mercadopago\.com\/v1\/payments\/(\d+)$/);
    if (m) {
      const p = pagamentos.get(m[1]);
      return p ? Response.json(p) : Response.json({ message: 'not found' }, { status: 404 });
    }
    if (u === 'https://api.brevo.com/v3/smtp/email') {
      return Response.json({ messageId: 'x' }, { status: 201 });
    }
    throw new Error(`fetch inesperado: ${u}`);
  };
});

afterEach(() => {
  globalThis.fetch = fetchOriginal;
});

function pagamento(id, extra = {}) {
  const p = {
    id: Number(id),
    status: 'approved',
    currency_id: 'BRL',
    transaction_amount: 69,
    external_reference: 'ML-abc123',
    date_approved: '2026-10-04T12:00:00.000-03:00',
    payer: { email: 'Comprador@Email.com' },
    ...extra,
  };
  pagamentos.set(String(id), p);
  return p;
}

const pedir = (caminho, init) => worker.fetch(new Request(`${ORIGEM}${caminho}`, init), env);
const emails = () => chamadas.filter((c) => c.url.includes('brevo'));
const codigoNa = (html) => html.match(/MAPLONG-[\w-]+\.[\w-]+/)?.[0];

test('a página inicial mostra o preço', async () => {
  const r = await pedir('/');
  assert.equal(r.status, 200);
  assert.match(await r.text(), /R\$ 69,00/);
});

test('comprar cria o pagamento de R$ 69,00 e redireciona ao Mercado Pago', async () => {
  const r = await pedir('/comprar?email=Ana@Email.com');
  assert.equal(r.status, 303);
  assert.match(r.headers.get('location'), /mercadopago\.com\.br/);
  const pref = chamadas.find((c) => c.url.endsWith('/checkout/preferences'));
  assert.equal(pref.metodo, 'POST');
  assert.equal(pref.headers.authorization, 'Bearer APP_USR-teste');
  assert.equal(pref.corpo.items[0].unit_price, 69);
  assert.equal(pref.corpo.items[0].currency_id, 'BRL');
  assert.match(pref.corpo.external_reference, /^ML-[0-9a-f]{32}$/);
  assert.equal(pref.corpo.notification_url, `${ORIGEM}/webhook/mercadopago`);
  assert.equal(pref.corpo.back_urls.success, `${ORIGEM}/obrigado`);
  assert.deepEqual(pref.corpo.payer, { email: 'ana@email.com' });
});

test('sem o token do Mercado Pago a loja avisa que está em configuração', async () => {
  delete env.MP_ACCESS_TOKEN;
  const r = await pedir('/comprar');
  assert.equal(r.status, 503);
  assert.match(await r.text(), /MP_ACCESS_TOKEN/);
});

test('depois de pagar, a página de retorno mostra o código válido', async () => {
  pagamento('555');
  const r = await pedir('/obrigado?payment_id=555&status=approved&external_reference=ML-abc123');
  assert.equal(r.status, 200);
  const codigo = codigoNa(await r.text());
  const lic = await conferirLicenca(codigo, chaves.publica);
  assert.deepEqual(lic, { id: 'MP-555', plano: 'pro', email: 'comprador@email.com', data: '2026-10-04' });
});

test('a página de retorno não mostra código de compra de outra pessoa', async () => {
  pagamento('555');
  const r = await pedir('/obrigado?payment_id=555&external_reference=ML-chute');
  assert.equal(r.status, 404);
  assert.equal(codigoNa(await r.text()), undefined);
  const r2 = await pedir('/obrigado?payment_id=999&external_reference=ML-abc123');
  assert.equal(r2.status, 404);
});

test('Pix pendente: a página espera e se atualiza sozinha', async () => {
  pagamento('556', { status: 'pending' });
  const r = await pedir('/obrigado?payment_id=556&external_reference=ML-abc123');
  const html = await r.text();
  assert.match(html, /http-equiv="refresh"/);
  assert.equal(codigoNa(html), undefined);
});

test('pagamento com valor menor não gera licença', async () => {
  pagamento('557', { transaction_amount: 1 });
  const r = await pedir('/obrigado?payment_id=557&external_reference=ML-abc123');
  assert.equal(codigoNa(await r.text()), undefined);
  await pedir('/webhook/mercadopago', { method: 'POST', body: JSON.stringify({ type: 'payment', data: { id: '557' } }) });
  assert.equal(emails().length, 0);
});

test('o aviso de pagamento aprovado envia o código por e-mail uma única vez', async () => {
  env.LICENCAS = kv();
  pagamento('600');
  const aviso = () =>
    pedir('/webhook/mercadopago?data.id=600&type=payment', {
      method: 'POST',
      body: JSON.stringify({ action: 'payment.updated', type: 'payment', data: { id: '600' } }),
    });
  assert.equal((await aviso()).status, 200);
  assert.equal((await aviso()).status, 200);
  assert.equal(emails().length, 1);
  const enviado = emails()[0].corpo;
  assert.deepEqual(enviado.to, [{ email: 'comprador@email.com' }]);
  assert.equal(enviado.sender.email, 'vendas@exemplo.com');
  const lic = await conferirLicenca(codigoNa(enviado.htmlContent), chaves.publica);
  assert.equal(lic.id, 'MP-600');
  assert.ok(env.LICENCAS.m.has('licenca:MP-600'));
});

test('avisos de pagamento pendente ou de outro tipo são ignorados', async () => {
  pagamento('601', { status: 'pending' });
  await pedir('/webhook/mercadopago', { method: 'POST', body: JSON.stringify({ type: 'payment', data: { id: '601' } }) });
  await pedir('/webhook/mercadopago?topic=merchant_order&id=77', { method: 'POST' });
  assert.equal(emails().length, 0);
});

test('com o segredo configurado, avisos com assinatura falsa são recusados', async () => {
  env.MP_WEBHOOK_SECRET = 'segredo-do-painel';
  pagamento('700');
  const ts = '1760000000';
  const manifesto = `id:700;request-id:req-1;ts:${ts};`;
  const v1 = createHmac('sha256', env.MP_WEBHOOK_SECRET).update(manifesto).digest('hex');
  const enviar = (assinatura) =>
    pedir('/webhook/mercadopago?data.id=700&type=payment', {
      method: 'POST',
      headers: { 'x-signature': `ts=${ts},v1=${assinatura}`, 'x-request-id': 'req-1' },
      body: JSON.stringify({ type: 'payment', data: { id: '700' } }),
    });
  assert.equal((await enviar('0'.repeat(64))).status, 401);
  assert.equal(emails().length, 0);
  assert.equal((await enviar(v1)).status, 200);
  assert.equal(emails().length, 1);
});

test('gerador on-line: exige a senha e gera licença de proprietário', async () => {
  const form = (campos) => ({ method: 'POST', body: new URLSearchParams(campos) });
  const errada = await pedir('/admin', form({ senha: 'chute', email: 'eu@email.com', plano: 'dono' }));
  assert.equal(errada.status, 401);
  assert.equal(codigoNa(await errada.text()), undefined);

  const r = await pedir('/admin', form({ senha: 'senha-forte-de-teste', email: 'Eu@Email.com', plano: 'dono' }));
  assert.equal(r.status, 200);
  const lic = await conferirLicenca(codigoNa(await r.text()), chaves.publica);
  assert.equal(lic.plano, 'dono');
  assert.equal(lic.email, 'eu@email.com');
  assert.match(lic.id, /^DONO-/);
});

test('gerador on-line: recupera o código de uma venda pelo número do pagamento', async () => {
  pagamento('800');
  const r = await pedir('/admin', {
    method: 'POST',
    body: new URLSearchParams({ senha: 'senha-forte-de-teste', pagamento: '800', enviar: '1' }),
  });
  const lic = await conferirLicenca(codigoNa(await r.text()), chaves.publica);
  assert.equal(lic.id, 'MP-800');
  assert.equal(emails().length, 1);
});

test('gerador on-line desativado sem senha configurada', async () => {
  delete env.ADMIN_PASSWORD;
  assert.equal((await pedir('/admin')).status, 503);
  const r = await pedir('/admin', { method: 'POST', body: new URLSearchParams({ senha: '' }) });
  assert.equal(r.status, 503);
});

test('saúde mostra o que está configurado sem revelar segredos', async () => {
  const r = await pedir('/saude');
  const j = await r.json();
  assert.equal(j.preco, 69);
  assert.equal(j.mercadoPago, true);
  assert.equal(j.email, true);
  assert.ok(!JSON.stringify(j).includes('APP_USR'));
});
