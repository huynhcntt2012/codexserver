import type { AppProps } from 'next/app';
import Head from 'next/head';
import { SessionProvider } from '@/lib/session';
import '@/styles/globals.css';

export default function AdminApp({ Component, pageProps }: AppProps) {
  return (
    <SessionProvider>
      <Head>
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="robots" content="noindex, nofollow" />
        <title>Bụp Bụp Admin</title>
      </Head>
      <Component {...pageProps} />
    </SessionProvider>
  );
}
