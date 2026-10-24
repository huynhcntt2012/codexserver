import { Head, Html, Main, NextScript } from 'next/document';

export default function Document() {
  return (
    <Html lang="vi">
      <Head>
        <meta name="theme-color" content="#0d2f5c" />
        <link rel="icon" href="/admin/game/ui/launch/mascot_pip.png" />
      </Head>
      <body>
        <Main />
        <NextScript />
      </body>
    </Html>
  );
}
