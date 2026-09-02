import { randomBytes } from 'node:crypto';

function loadSecret(name: 'JWT_SECRET' | 'JWT_REFRESH_SECRET'): string {
  const configured = process.env[name];
  if (configured && configured.length >= 32) return configured;
  if (process.env.NODE_ENV === 'production') {
    throw new Error(
      `${name} must contain at least 32 characters in production`,
    );
  }
  return randomBytes(48).toString('base64url');
}

export const jwtSecret = loadSecret('JWT_SECRET');
export const jwtRefreshSecret = loadSecret('JWT_REFRESH_SECRET');
