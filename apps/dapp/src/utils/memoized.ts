import { VMap } from './vmap';

export interface MemoizedAsyncValue<T> {
  get(): Promise<T>;
}

type MemoizedAsyncValueState<T> =
  | { state: 'empty' }
  | { state: 'loading'; promise: Promise<T> }
  | { state: 'ready'; value: T };

export function createMemoizedAsyncValue<T>(
  loadfn: () => Promise<T>
): MemoizedAsyncValue<T> {
  let cvalue: MemoizedAsyncValueState<T> = { state: 'empty' };

  async function get(): Promise<T> {
    async function doLoad() {
      const value = await loadfn();
      cvalue = { state: 'ready', value };
      return value;
    }

    switch (cvalue.state) {
      case 'empty': {
        const promise = doLoad();
        cvalue = { state: 'loading', promise };
        return promise;
      }
      case 'loading':
        return cvalue.promise;
      case 'ready':
        return cvalue.value;
    }
  }

  return { get };
}

export function memoizedAsyncValue<T>(v: T): MemoizedAsyncValue<T> {
  return createMemoizedAsyncValue(async () => v);
}

export interface MemoizedAsyncMap<K, V> {
  get(key: K): Promise<V>;
  clear(): void;
}

type MemoizedAsyncMapState<T> =
  | { state: 'loading'; promise: Promise<T> }
  | { state: 'ready'; value: T };

export function createMemoizedAsyncMap<K, V>(
  keyfn: (key: K) => string,
  loadfn: (key: K) => Promise<V>
): MemoizedAsyncMap<K, V> {
  const map: VMap<K, MemoizedAsyncMapState<V>> = new VMap(keyfn);

  async function get(key: K): Promise<V> {
    async function doLoad(): Promise<V> {
      const value = await loadfn(key);
      map.put(key, { state: 'ready', value });
      return value;
    }

    const value = map.get(key);
    if (value === undefined) {
      const promise = doLoad();
      map.put(key, { state: 'loading', promise });
      return promise;
    } else {
      switch (value.state) {
        case 'loading':
          return value.promise;
        case 'ready':
          return value.value;
      }
    }
  }

  function clear() {
    map.clear();
  }

  return { get, clear };
}
