import type { FastifyInstance, FastifyPluginAsync } from 'fastify';

/**
 * Minimaler Ersatz für fastify-plugin: Plugin ohne eigene Kapselung registrieren,
 * damit Dekorationen (z. B. requireUser) global sichtbar sind.
 */
export default function fp<T extends FastifyPluginAsync>(fn: T): T {
  (fn as unknown as Record<symbol, boolean>)[Symbol.for('skip-override')] = true;
  return fn;
}

export type { FastifyInstance };
