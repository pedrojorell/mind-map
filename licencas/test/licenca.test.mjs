import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

import {
  ErroLicenca,
  assinarLicenca,
  conferirLicenca,
  gerarChaves,
} from '../src/licenca.js';

const fixture = JSON.parse(
  readFileSync(new URL('../../test/fixtures/licenca_teste.json', import.meta.url), 'utf8'),
);

test('gera e confere uma licença', async () => {
  const { privada, publica } = await gerarChaves();
  const codigo = await assinarLicenca(privada, { id: 'MP-1', email: ' Ana@Email.com ' });
  assert.match(codigo, /^MAPLONG-[\w-]+\.[\w-]+$/);
  const lic = await conferirLicenca(codigo, publica);
  assert.equal(lic.id, 'MP-1');
  assert.equal(lic.email, 'ana@email.com');
  assert.equal(lic.plano, 'pro');
  assert.match(lic.data, /^\d{4}-\d{2}-\d{2}$/);
});

test('o mesmo pedido gera sempre o mesmo código', async () => {
  const { privada } = await gerarChaves();
  const dados = { id: 'MP-9', email: 'a@b.com', data: '2026-01-02' };
  assert.equal(await assinarLicenca(privada, dados), await assinarLicenca(privada, dados));
});

test('aceita espaços e quebras de linha ao colar', async () => {
  const c = fixture.pro.codigo;
  const colado = `  "${c.slice(0, 50)}\n${c.slice(50, 120)}\r\n ${c.slice(120)} "  `;
  const lic = await conferirLicenca(colado, fixture.chavePublica);
  assert.equal(lic.email, fixture.pro.email);
});

test('confere os códigos de exemplo usados também nos testes do app', async () => {
  for (const caso of [fixture.pro, fixture.dono]) {
    const lic = await conferirLicenca(caso.codigo, fixture.chavePublica);
    assert.deepEqual(lic, { id: caso.id, plano: caso.plano, email: caso.email, data: caso.data });
  }
});

test('recusa códigos alterados, de outra chave ou incompletos', async () => {
  const outra = await gerarChaves();
  const c = fixture.pro.codigo;
  const [dados, assinatura] = c.slice('MAPLONG-'.length).split('.');
  const json = JSON.parse(Buffer.from(dados, 'base64url').toString());
  json.p = 'dono';
  const alterado = `MAPLONG-${Buffer.from(JSON.stringify(json)).toString('base64url')}.${assinatura}`;

  await assert.rejects(conferirLicenca(alterado, fixture.chavePublica), ErroLicenca);
  await assert.rejects(conferirLicenca(c, outra.publica), /inválido/);
  await assert.rejects(conferirLicenca(c.slice(0, 60), fixture.chavePublica), /incompleto/);
  await assert.rejects(conferirLicenca('ABC-123', fixture.chavePublica), /MAPLONG-/);
  await assert.rejects(conferirLicenca('MAPLONG-a$b.c', fixture.chavePublica), /caracteres/);
});

test('valida os dados antes de assinar', async () => {
  const { privada } = await gerarChaves();
  await assert.rejects(assinarLicenca(privada, { id: 'X', email: 'sem-arroba' }), /E-mail/);
  await assert.rejects(assinarLicenca(privada, { id: 'X', email: 'a@b.com', plano: 'gratis' }), /Plano/);
  await assert.rejects(assinarLicenca(privada, { id: 'com espaço', email: 'a@b.com' }), /Identificador/);
  await assert.rejects(assinarLicenca({ kty: 'RSA' }, { id: 'X', email: 'a@b.com' }), /Chave privada/);
});
