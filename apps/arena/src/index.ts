import { createArenaServer } from './server.js';

const { listen } = createArenaServer();
await listen(Number(process.env.PORT ?? 2567));
console.info('Suni Bomb Arena listening on port', process.env.PORT ?? 2567);
