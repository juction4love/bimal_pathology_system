import { lazy, type ComponentType, type LazyExoticComponent } from 'react';

const RELOAD_KEY_PREFIX = 'bimal-lis:chunk-reload:';

export function isChunkLoadError(error: unknown): boolean {
  const message = error instanceof Error ? error.message : String(error ?? '');
  return /Failed to fetch dynamically imported module|Importing a module script failed|ChunkLoadError|Loading chunk [\w-]+ failed/i.test(message);
}

function reloadKey(routeName: string): string {
  return `${RELOAD_KEY_PREFIX}${routeName}:${window.location.pathname}`;
}

export function clearChunkReloadMarkers(): void {
  for (let index = sessionStorage.length - 1; index >= 0; index -= 1) {
    const key = sessionStorage.key(index);
    if (key?.startsWith(RELOAD_KEY_PREFIX)) sessionStorage.removeItem(key);
  }
}

export function lazyWithChunkRecovery<T extends ComponentType<any>>(
  routeName: string,
  importer: () => Promise<{ default: T }>,
): LazyExoticComponent<T> {
  return lazy(async () => {
    const key = reloadKey(routeName);
    try {
      const module = await importer();
      sessionStorage.removeItem(key);
      return module;
    } catch (error) {
      if (!isChunkLoadError(error)) throw error;
      if (sessionStorage.getItem(key) !== 'attempted') {
        sessionStorage.setItem(key, 'attempted');
        window.location.reload();
        return new Promise<never>(() => undefined);
      }
      throw new Error('A newer application version is available. Refresh to load the current page.', { cause: error });
    }
  });
}
