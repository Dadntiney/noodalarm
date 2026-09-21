import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '../../..');

function readHtmlConfig() {
  const html = fs.readFileSync(path.join(ROOT, 'noodalarm.html'), 'utf8');
  const url = html.match(/SUPABASE_URL\s*=\s*'([^']+)'/)?.[1];
  const anon = html.match(/SUPABASE_ANON_KEY\s*=\s*'([^']+)'/)?.[1];
  if (!url || !anon) throw new Error('Kon SUPABASE_URL / ANON_KEY niet uit noodalarm.html lezen');
  return { url, anon };
}

function loadDotEnv() {
  const envPath = path.join(ROOT, '.env.local');
  if (!fs.existsSync(envPath)) return;
  for (const line of fs.readFileSync(envPath, 'utf8').split('\n')) {
    const m = line.match(/^([A-Z0-9_]+)=(.*)$/);
    if (!m) continue;
    if (!(m[1] in process.env)) process.env[m[1]] = m[2].replace(/^"|"$/g, '');
  }
}

loadDotEnv();
const htmlCfg = readHtmlConfig();

export const config = {
  supabaseUrl: process.env.SUPABASE_URL || htmlCfg.url,
  anonKey: process.env.SUPABASE_ANON_KEY || htmlCfg.anon,
  accessToken: process.env.SUPABASE_ACCESS_TOKEN || '',
  projectRef: process.env.SUPABASE_PROJECT_REF || 'vdohfnmhzbttqmsinoln',
  password: process.env.NORI_SUITE_PASSWORD || 'TestLoad3064!',
  /** Alle suite-users beginnen met dit prefix (max 20 chars username). */
  prefix: 'lt',
  noriSystemId: '961b3add-ad24-4e56-8c43-461676800cb2'
};

export function functionsUrl(name) {
  return `${config.supabaseUrl}/functions/v1/${name}`;
}
