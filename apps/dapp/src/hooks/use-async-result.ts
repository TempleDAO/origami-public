import {
  DependencyList,
  useEffect,
  useState,
  useCallback,
  useRef,
} from 'react';
import { Loading, loading, ready } from '@/utils/loading-value';

/**
 * A hook that runs an async function to fetch a value.
 *
 * Returns the state, and a function to reload if required. If multiple calls
 * are concurrent, the most recent result will be kept.
 */
export function useAsyncResult<T>(
  initial: T,
  fn: () => Promise<T>,
  deps?: DependencyList
): [T, (t: T) => Promise<void>] {
  const asyncResultId = useRef(0);
  const [_value, _setValue] = useState<[T, number]>(() => [
    initial,
    asyncResultId.current++,
  ]);

  function setValue(t: T, id: number) {
    // Only update if the result is not old.
    _setValue(([existingValue, existingId]) => {
      return id >= existingId ? [t, id] : [existingValue, existingId];
    });
  }

  async function loadValue(initial: T) {
    const id = asyncResultId.current++;
    setValue(initial, id);
    const v = await fn();
    setValue(v, id);
  }

  useEffect(() => {
    loadValue(initial);
    /* eslint-disable-next-line */
  }, deps || []);

  const [value] = _value;
  return [value, loadValue];
}

/**
 * A hook that periodically runs an async function to fetch a value.
 *
 * Returns the state, and a function to reload if required.
 */
export function useAsyncResultPerodic<T>(
  initial: T,
  intervalMs: number,
  fn: () => Promise<T>
): [T] {
  const [value, setValue] = useState<T>(initial);

  const loadValue = useCallback(async () => {
    const v = await fn();
    setValue(v);
  }, [fn]);

  useEffect(() => {
    loadValue();
    const id = setInterval(loadValue, intervalMs);

    return () => clearInterval(id);
  }, [intervalMs, loadValue]);

  return [value];
}

export function useAsyncLoad<T>(
  fn: () => Promise<T>,
  deps?: DependencyList
): [Loading<T>, () => Promise<void>] {
  const [value, refresh] = useAsyncResult(
    loading<T>(),
    async () => {
      const v = await fn();
      return ready(v);
    },
    deps
  );
  return [value, () => refresh(loading())];
}

export function useAsyncLoadPeriodic<T>(
  intervalMs: number,
  fn: () => Promise<T>,
  deps?: DependencyList
): [Loading<T>] {
  const [value, setValue] = useState<Loading<T>>(loading());

  async function loadValue() {
    const v = await fn();
    setValue(ready(v));
  }

  useEffect(() => {
    loadValue();
    const id = setInterval(loadValue, intervalMs);

    return () => clearInterval(id);
    /* eslint-disable-next-line */
  }, deps);

  return [value];
}

// Maps over an array asynchronously
export function useMapAsyncFn<A, B>(
  as: A[], // The input values
  bInitialFn: (a: A) => B, // A non-asnyc function to generate the initial mapped values
  bAsyncFn: (a: A) => Promise<B>, // An async function to generate the final values
  deps?: DependencyList
): B[] {
  const [bs, setBs] = useState(() => as.map(bInitialFn));

  useEffect(() => {
    async function update(i: number) {
      const newb = await bAsyncFn(as[i]);
      setBs((bs) => {
        const bs2 = [...bs];
        bs2[i] = newb;
        return bs2;
      });
    }
    for (let i = 0; i < as.length; i++) {
      update(i);
    }
    /* eslint-disable-next-line */
  }, deps);

  return bs;
}
