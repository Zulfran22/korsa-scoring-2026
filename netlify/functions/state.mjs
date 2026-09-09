import { getStore } from '@netlify/blobs';

/*
 * Backend state sync untuk korsa-scoring-2026.html saat dihosting di Netlify.
 * Endpoint ini dipanggil sebagai /api/state (lihat config.path di bawah) oleh
 * client - GET mengambil skor terakhir, POST menyimpan skor terbaru. Dipakai
 * supaya admin & display bisa dibuka dari dua perangkat/browser berbeda.
 *
 * getStore({ name }) tanpa deploy-scoping berarti data ini "site-wide": tetap
 * ada walau situsnya di-deploy ulang (push ke GitHub lagi), tidak ikut ke-reset.
 */
export default async (req) => {
  const store = getStore({ name: 'korsa-state', consistency: 'strong' });

  if (req.method === 'GET') {
    const data = await store.get('state', { type: 'text' });
    return new Response(data || '{}', {
      headers: { 'Content-Type': 'application/json; charset=utf-8' }
    });
  }

  if (req.method === 'POST') {
    const body = await req.text();
    try {
      JSON.parse(body);
    } catch (e) {
      return new Response('bad json', { status: 400 });
    }
    await store.set('state', body);
    return new Response(null, { status: 204 });
  }

  return new Response('Method not allowed', { status: 405 });
};

export const config = {
  path: '/api/state'
};
