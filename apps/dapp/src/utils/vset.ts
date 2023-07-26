/**
 * A Set with values of arbitrary type V
 *
 * The constructor is passed a function to map a value of type V to a string.
 */

export class VSet<V> {
  _values: { [key: string]: V };

  constructor(readonly keygen: (v: V) => string) {
    this._values = {};
  }

  has(v: V): boolean {
    return this._values[this.keygen(v)] != undefined;
  }

  add(v: V) {
    this._values[this.keygen(v)] = v;
  }

  addAll(vs: V[]) {
    for (const v of vs) {
      this.add(v);
    }
  }

  values(): V[] {
    return Object.values(this._values);
  }

  size(): number {
    return Object.keys(this._values).length;
  }
}

export type Result<T, E> = { kind: 'ok'; value: T } | { kind: 'err'; error: E };
