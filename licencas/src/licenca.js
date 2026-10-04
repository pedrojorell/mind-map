// Licenças do MapLong.
//
// Uma licença é um código assinado com Ed25519:
//
//   MAPLONG-<dados>.<assinatura>
//
// <dados> é um JSON curto em base64url, por exemplo
//   {"v":1,"id":"MP-123","p":"pro","e":"cliente@email.com","d":"2026-10-04"}
// e <assinatura> são os 64 bytes da assinatura desses dados, em base64url.
//
// Só quem tem a CHAVE PRIVADA consegue criar códigos válidos. O aplicativo
// guarda apenas a chave pública, que serve para conferir a assinatura (sem
// internet). Este arquivo roda no Node.js (gerador) e no Cloudflare Workers
// (servidor de vendas), pois usa só a Web Crypto API padrão.

export const PREFIXO = 'MAPLONG-';

/** Planos: "pro" (cliente que pagou) e "dono" (acesso do proprietário). */
export const PLANOS = ['pro', 'dono'];

const ALGORITMO = { name: 'Ed25519' };
const texto = new TextEncoder();
const leitor = new TextDecoder();

export function paraBase64Url(bytes) {
  let bin = '';
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export function deBase64Url(s) {
  if (!/^[A-Za-z0-9_-]*$/.test(s)) throw new ErroLicenca('Código com caracteres inválidos.');
  const b64 = s.replace(/-/g, '+').replace(/_/g, '/');
  const bin = atob(b64 + '='.repeat((4 - (b64.length % 4)) % 4));
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}

export class ErroLicenca extends Error {}

/** Remove espaços, quebras de linha e aspas que vêm junto ao copiar. */
export function normalizarCodigo(codigo) {
  return String(codigo ?? '').replace(/[\s"'`<>]/g, '');
}

export function normalizarEmail(email) {
  return String(email ?? '').trim().toLowerCase();
}

export function emailValido(email) {
  return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email);
}

/** Data de hoje (ou de [quando]) no formato AAAA-MM-DD. */
export function dataIso(quando = new Date()) {
  return new Date(quando).toISOString().slice(0, 10);
}

/** Cria um novo par de chaves. Guarde a privada em segurança. */
export async function gerarChaves() {
  const par = await crypto.subtle.generateKey(ALGORITMO, true, ['sign', 'verify']);
  const privada = await crypto.subtle.exportKey('jwk', par.privateKey);
  const publica = new Uint8Array(await crypto.subtle.exportKey('raw', par.publicKey));
  return {
    privada: { kty: privada.kty, crv: privada.crv, d: privada.d, x: privada.x },
    publica: paraBase64Url(publica),
  };
}

/** Lê a chave privada (objeto JWK ou o texto JSON dele). */
export async function importarChavePrivada(jwk) {
  const dados = typeof jwk === 'string' ? JSON.parse(jwk) : jwk;
  if (dados?.kty !== 'OKP' || dados?.crv !== 'Ed25519' || !dados?.d || !dados?.x) {
    throw new ErroLicenca('Chave privada inválida (esperado um JWK Ed25519).');
  }
  return crypto.subtle.importKey('jwk', dados, ALGORITMO, false, ['sign']);
}

async function importarChavePublica(publicaB64) {
  return crypto.subtle.importKey('raw', deBase64Url(publicaB64), ALGORITMO, false, ['verify']);
}

/**
 * Gera o código de licença.
 * @param chavePrivada CryptoKey (de importarChavePrivada) ou JWK.
 * @param dados {id, email, plano = 'pro', data = hoje}
 */
export async function assinarLicenca(chavePrivada, { id, email, plano = 'pro', data } = {}) {
  const e = normalizarEmail(email);
  if (!emailValido(e)) throw new ErroLicenca(`E-mail inválido: "${email ?? ''}"`);
  if (!PLANOS.includes(plano)) throw new ErroLicenca(`Plano inválido: "${plano}"`);
  if (!id || !/^[A-Za-z0-9_-]{1,64}$/.test(String(id))) {
    throw new ErroLicenca(`Identificador inválido: "${id ?? ''}"`);
  }
  const chave = chavePrivada instanceof CryptoKey ? chavePrivada : await importarChavePrivada(chavePrivada);
  // A ordem dos campos é fixa: o mesmo pedido gera sempre o mesmo código.
  const carga = texto.encode(
    JSON.stringify({ v: 1, id: String(id), p: plano, e, d: data ?? dataIso() }),
  );
  const assinatura = new Uint8Array(await crypto.subtle.sign(ALGORITMO, chave, carga));
  return `${PREFIXO}${paraBase64Url(carga)}.${paraBase64Url(assinatura)}`;
}

/**
 * Confere um código. Retorna {id, plano, email, data} ou lança ErroLicenca.
 */
export async function conferirLicenca(codigo, chavePublicaB64) {
  const c = normalizarCodigo(codigo);
  if (!c.toUpperCase().startsWith(PREFIXO)) {
    throw new ErroLicenca('O código deve começar com MAPLONG-.');
  }
  const partes = c.slice(PREFIXO.length).split('.');
  if (partes.length !== 2 || !partes[0] || !partes[1]) {
    throw new ErroLicenca('Código incompleto. Copie o código inteiro.');
  }
  const carga = deBase64Url(partes[0]);
  const assinatura = deBase64Url(partes[1]);
  const chave = await importarChavePublica(chavePublicaB64);
  const ok = assinatura.length === 64 &&
    (await crypto.subtle.verify(ALGORITMO, chave, assinatura, carga));
  if (!ok) throw new ErroLicenca('Código inválido.');
  const j = JSON.parse(leitor.decode(carga));
  return { id: j.id, plano: j.p, email: j.e, data: j.d };
}
