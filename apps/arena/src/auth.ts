import { ServerError } from '@colyseus/core';
import { jwtVerify } from 'jose';

export async function authenticate(token: unknown) {
  if (typeof token !== 'string' || token.length > 4096)
    throw new ServerError(401, 'Missing access token');
  try {
    const { payload } = await jwtVerify(
      token,
      new TextEncoder().encode(process.env.JWT_SECRET),
      { algorithms: ['HS256'], issuer: 'suni-api', audience: 'suni-arena' },
    );
    if (
      typeof payload.sub !== 'string' ||
      !payload.exp ||
      typeof payload.name !== 'string'
    )
      throw new Error('Invalid identity');
    return { accountId: payload.sub, name: payload.name };
  } catch {
    throw new ServerError(401, 'Invalid access token');
  }
}
