import { AppError } from './errors';

export interface RateBinding { limit(input: { key: string }): Promise<{ success: boolean }> }
export interface RateEnv { REQUEST_LIMITER?: RateBinding; INSTALL_LIMITER?: RateBinding }
const buckets = new Map<string, { count: number; until: number }>();

export async function limitRequest(ip: string, action: string, env: RateEnv): Promise<void> {
  const rules = [{ key: `request:${ip}`, binding: env.REQUEST_LIMITER, maximum: 60 }, ...(action === 'install' ? [{ key: `install:${ip}`, binding: env.INSTALL_LIMITER, maximum: 3 }] : [])];
  for (const rule of rules) {
    if (rule.binding) {
      if (!(await rule.binding.limit({ key: rule.key })).success) throw new AppError('RATE_LIMIT', '操作过于频繁，请稍后再试。', 429);
    } else {
      const now = Date.now();
      if (buckets.size > 10_000) for (const [key, value] of buckets) if (value.until <= now) buckets.delete(key);
      if (buckets.size > 20_000 && !buckets.has(rule.key)) throw new AppError('RATE_LIMIT', '网站暂时繁忙，请稍后再试。', 429);
      const bucket = buckets.get(rule.key);
      if (bucket && bucket.until > now) {
        if (++bucket.count > rule.maximum) throw new AppError('RATE_LIMIT', '操作过于频繁，请稍后再试。', 429);
      } else buckets.set(rule.key, { count: 1, until: now + 60_000 });
    }
  }
}
