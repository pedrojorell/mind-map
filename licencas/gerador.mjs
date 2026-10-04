#!/usr/bin/env node
// Gerador de licenças do MapLong (uso do proprietário).
//
//   node gerador.mjs                         modo interativo (pergunta tudo)
//   node gerador.mjs gerar <email> [--dono]  gera um código
//   node gerador.mjs conferir <codigo>       confere um código
//   node gerador.mjs chaves [pasta]          cria o par de chaves (uma vez só)
//
// A chave privada é lida de --chave <arquivo>, da variável MAPLONG_CHAVE ou
// do arquivo chave-privada.json na mesma pasta deste gerador.

import { spawnSync } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { createInterface } from 'node:readline/promises';
import { fileURLToPath } from 'node:url';

import {
  ErroLicenca,
  assinarLicenca,
  conferirLicenca,
  emailValido,
  gerarChaves,
  importarChavePrivada,
  normalizarEmail,
} from './src/licenca.js';

const pasta = dirname(fileURLToPath(import.meta.url));

function opcao(args, nome) {
  const i = args.indexOf(nome);
  if (i < 0) return undefined;
  const v = args[i + 1];
  args.splice(i, 2);
  return v;
}

function bandeira(args, nome) {
  const i = args.indexOf(nome);
  if (i < 0) return false;
  args.splice(i, 1);
  return true;
}

function caminhoChave(args) {
  return resolve(opcao(args, '--chave') ?? process.env.MAPLONG_CHAVE ?? join(pasta, 'chave-privada.json'));
}

function lerChave(caminho) {
  if (!existsSync(caminho)) {
    throw new ErroLicenca(
      `Chave privada não encontrada em ${caminho}.\n` +
        'Crie uma com "node gerador.mjs chaves" ou informe --chave <arquivo>.',
    );
  }
  return JSON.parse(readFileSync(caminho, 'utf8'));
}

/** A chave pública fica dentro do próprio JWK privado (campo "x"). */
function publicaDe(jwk) {
  return jwk.x;
}

function copiar(textoParaCopiar) {
  const cmd = process.platform === 'win32' ? 'clip' : process.platform === 'darwin' ? 'pbcopy' : null;
  if (!cmd) return false;
  try {
    return spawnSync(cmd, { input: textoParaCopiar }).status === 0;
  } catch {
    return false;
  }
}

function novoId(plano) {
  const sufixo = randomBytes(5).toString('hex').toUpperCase();
  return `${plano === 'dono' ? 'DONO' : 'MANUAL'}-${sufixo}`;
}

async function gerar(jwk, email, plano, id) {
  const chave = await importarChavePrivada(jwk);
  const codigo = await assinarLicenca(chave, { id: id ?? novoId(plano), email, plano });
  // Confere antes de entregar: garante que o app vai aceitar.
  await conferirLicenca(codigo, publicaDe(jwk));
  return codigo;
}

function mostrar(codigo, email, plano) {
  console.log(`\nLicença ${plano === 'dono' ? 'de PROPRIETÁRIO' : 'Pro'} para ${email}:\n`);
  console.log(codigo);
  console.log(copiar(codigo) ? '\n(copiado para a área de transferência)' : '');
}

async function interativo(args) {
  const jwk = lerChave(caminhoChave(args));
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  console.log('=== Gerador de licenças do MapLong ===\n');
  try {
    for (;;) {
      const email = normalizarEmail(await rl.question('E-mail do cliente (Enter para sair): '));
      if (!email) break;
      if (!emailValido(email)) {
        console.log('E-mail inválido. Tente de novo.\n');
        continue;
      }
      const tipo = (await rl.question('Plano: [1] Pro (cliente)  [2] Proprietário  > ')).trim();
      const plano = tipo === '2' ? 'dono' : 'pro';
      mostrar(await gerar(jwk, email, plano), email, plano);
      console.log('Envie esse código ao cliente. Ele cola em Configurações > Licença.\n');
    }
  } finally {
    rl.close();
  }
}

async function criarChaves(args) {
  const destino = resolve(args[0] ?? pasta);
  const arquivo = join(destino, 'chave-privada.json');
  if (existsSync(arquivo)) {
    throw new ErroLicenca(
      `Já existe uma chave em ${arquivo}.\n` +
        'Criar outra invalida todas as licenças já vendidas. Nada foi alterado.',
    );
  }
  mkdirSync(destino, { recursive: true });
  const { privada, publica } = await gerarChaves();
  const senhaAdmin = randomBytes(18).toString('base64url');
  writeFileSync(arquivo, JSON.stringify(privada, null, 2) + '\n', { mode: 0o600 });
  writeFileSync(join(destino, 'chave-publica.txt'), publica + '\n');
  writeFileSync(
    join(destino, 'segredos-do-servidor.txt'),
    [
      'Valores para o servidor de vendas (Cloudflare). NÃO compartilhe.',
      '',
      'LICENSE_PRIVATE_KEY (cole a linha inteira):',
      JSON.stringify(privada),
      '',
      'ADMIN_PASSWORD (senha da página /admin do gerador on-line):',
      senhaAdmin,
      '',
    ].join('\n'),
    { mode: 0o600 },
  );
  console.log(`Chaves criadas em ${destino}`);
  console.log(`Chave pública (vai no app, em lib/licensing/license.dart):\n${publica}`);
  console.log('\nFaça uma cópia de segurança da pasta. Sem a chave privada não é');
  console.log('possível gerar novas licenças que o app aceite.');
}

async function main() {
  const args = process.argv.slice(2);
  const comando = args.shift();
  switch (comando) {
    case undefined:
      return interativo(args);
    case 'chaves':
      return criarChaves(args);
    case 'gerar': {
      const plano = bandeira(args, '--dono') ? 'dono' : 'pro';
      const id = opcao(args, '--id');
      const jwk = lerChave(caminhoChave(args));
      const email = args[0];
      return mostrar(await gerar(jwk, email, plano, id), normalizarEmail(email), plano);
    }
    case 'conferir': {
      const jwk = lerChave(caminhoChave(args));
      const lic = await conferirLicenca(args.join(''), publicaDe(jwk));
      console.log('Código válido:', lic);
      return;
    }
    default:
      console.log(readFileSync(fileURLToPath(import.meta.url), 'utf8').split('\n').slice(1, 11).join('\n'));
      process.exitCode = 1;
  }
}

main().catch((e) => {
  console.error(e instanceof ErroLicenca ? `Erro: ${e.message}` : e);
  process.exitCode = 1;
});
