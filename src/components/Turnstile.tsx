import { useEffect, useRef } from 'react';

declare global {
  interface Window {
    turnstile?: {
      render(container: HTMLElement, options: Record<string, unknown>): string;
      remove(id: string): void;
    };
  }
}

let loading: Promise<void> | undefined;
function load() {
  if (window.turnstile) return Promise.resolve();
  if (!loading) loading = new Promise<void>((resolve, reject) => {
    const script = document.createElement('script');
    script.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit';
    script.async = true;
    script.onload = () => resolve();
    script.onerror = () => { loading = undefined; script.remove(); reject(new Error('人机验证加载失败，请检查网络后刷新页面。')); };
    document.head.appendChild(script);
  });
  return loading;
}

export function Turnstile({ siteKey, onToken, onError }: { siteKey: string; onToken: (token: string) => void; onError: (error: string) => void }) {
  const container = useRef<HTMLDivElement>(null);
  const callbacks = useRef({ onToken, onError });
  callbacks.current = { onToken, onError };
  useEffect(() => {
    let cancelled = false;
    let widget: string | undefined;
    load().then(() => {
      if (cancelled || !container.current || !window.turnstile) return;
      widget = window.turnstile.render(container.current, {
        sitekey: siteKey, theme: 'light', size: 'flexible',
        callback: (token: string) => callbacks.current.onToken(token),
        'expired-callback': () => callbacks.current.onToken(''),
        'error-callback': () => callbacks.current.onError('人机验证未完成，请刷新后重试。'),
      });
    }).catch((error: Error) => callbacks.current.onError(error.message));
    return () => { cancelled = true; if (widget) window.turnstile?.remove(widget); };
  }, [siteKey]);
  return <div className="turnstile" ref={container} />;
}
