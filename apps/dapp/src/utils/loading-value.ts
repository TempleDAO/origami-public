export type Loading<T> = { state: 'loading' } | { state: 'ready'; value: T };

export interface Reloadable<T> {
  value: Loading<T>;
  refresh(): void;
}

export function newLoading<T>(value: T | undefined): Loading<T> {
  if (value === undefined) {
    return { state: 'loading' };
  } else {
    return { state: 'ready', value };
  }
}

export function loading<T>(): Loading<T> {
  return { state: 'loading' };
}

export function ready<T>(value: T): Loading<T> {
  return { state: 'ready', value };
}

export function isReady<T>(
  value: Loading<T>
): value is { state: 'ready'; value: T } {
  return value.state === 'ready';
}

export function getValue<T>(l: Loading<T>): T | undefined {
  if (l.state === 'ready') {
    return l.value;
  }
}

export function getWithDefault<T>(lv: Loading<T>, defv: T): T {
  if (lv.state === 'loading') {
    return defv;
  }
  return lv.value;
}

export function lmap<A, B>(l: Loading<A>, f: (a: A) => B): Loading<B> {
  if (l.state === 'loading') {
    return loading();
  }
  return ready(f(l.value));
}

export function lmap2<A1, A2, B>(
  ls: [Loading<A1>, Loading<A2>],
  f: (a1: A1, a2: A2) => B
): Loading<B> {
  const [la1, la2] = ls;
  if (la1.state === 'loading' || la2.state === 'loading') {
    return loading();
  }
  return ready(f(la1.value, la2.value));
}

export function lmap3<A1, A2, A3, B>(
  ls: [Loading<A1>, Loading<A2>, Loading<A3>],
  f: (a1: A1, a2: A2, a3: A3) => B
): Loading<B> {
  const [la1, la2, la3] = ls;
  if (
    la1.state === 'loading' ||
    la2.state === 'loading' ||
    la3.state === 'loading'
  ) {
    return loading();
  }
  return ready(f(la1.value, la2.value, la3.value));
}

export function lmap4<A1, A2, A3, A4, B>(
  ls: [Loading<A1>, Loading<A2>, Loading<A3>, Loading<A4>],
  f: (a1: A1, a2: A2, a3: A3, a4: A4) => B
): Loading<B> {
  const [la1, la2, la3, la4] = ls;
  if (
    la1.state === 'loading' ||
    la2.state === 'loading' ||
    la3.state === 'loading' ||
    la4.state === 'loading'
  ) {
    return loading();
  }
  return ready(f(la1.value, la2.value, la3.value, la4.value));
}

export function lmap5<A1, A2, A3, A4, A5, B>(
  ls: [Loading<A1>, Loading<A2>, Loading<A3>, Loading<A4>, Loading<A5>],
  f: (a1: A1, a2: A2, a3: A3, a4: A4, a5: A5) => B
): Loading<B> {
  const [la1, la2, la3, la4, la5] = ls;
  if (
    la1.state === 'loading' ||
    la2.state === 'loading' ||
    la3.state === 'loading' ||
    la4.state === 'loading' ||
    la5.state === 'loading'
  ) {
    return loading();
  }
  return ready(f(la1.value, la2.value, la3.value, la4.value, la5.value));
}

export function lmap6<A1, A2, A3, A4, A5, A6, B>(
  ls: [
    Loading<A1>,
    Loading<A2>,
    Loading<A3>,
    Loading<A4>,
    Loading<A5>,
    Loading<A6>
  ],
  f: (a1: A1, a2: A2, a3: A3, a4: A4, a5: A5, a6: A6) => B
): Loading<B> {
  const [la1, la2, la3, la4, la5, la6] = ls;
  if (
    la1.state === 'loading' ||
    la2.state === 'loading' ||
    la3.state === 'loading' ||
    la4.state === 'loading' ||
    la5.state === 'loading' ||
    la6.state === 'loading'
  ) {
    return loading();
  }
  return ready(
    f(la1.value, la2.value, la3.value, la4.value, la5.value, la6.value)
  );
}

export function lmap7<A1, A2, A3, A4, A5, A6, A7, B>(
  ls: [
    Loading<A1>,
    Loading<A2>,
    Loading<A3>,
    Loading<A4>,
    Loading<A5>,
    Loading<A6>,
    Loading<A7>
  ],
  f: (a1: A1, a2: A2, a3: A3, a4: A4, a5: A5, a6: A6, a7: A7) => B
): Loading<B> {
  const [la1, la2, la3, la4, la5, la6, la7] = ls;
  if (
    la1.state === 'loading' ||
    la2.state === 'loading' ||
    la3.state === 'loading' ||
    la4.state === 'loading' ||
    la5.state === 'loading' ||
    la6.state === 'loading' ||
    la7.state === 'loading'
  ) {
    return loading();
  }
  return ready(
    f(
      la1.value,
      la2.value,
      la3.value,
      la4.value,
      la5.value,
      la6.value,
      la7.value
    )
  );
}
