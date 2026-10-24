/** Static export served by the web nginx at /admin; the API is proxied at /admin/api. */
const config = {
  output: 'export',
  basePath: '/admin',
  trailingSlash: true,
  images: { unoptimized: true },
  poweredByHeader: false,
  reactStrictMode: true,
};

export default config;
