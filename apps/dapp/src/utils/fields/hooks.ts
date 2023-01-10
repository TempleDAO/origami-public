import { useState } from 'react';

import { FieldFns } from './type';

export interface TypedFieldState<T> {
  text: string;
  setText(s: string): void;

  isModified(): boolean;

  isValid(): boolean;
  value(): T;
  validationError(): string;

  setValue(t: T): void;

  revert(): void;
}

export interface FieldState {
  text: string;
  setText(s: string): void;
  initialText: string;
  setInitialText(s: string): void;
  id: string;
}

/**
 * Construct Fieldstate using react hooks
 */

export function useFieldState(): FieldState {
  const [text, setText] = useState<string>('');
  const [initialText, setInitialText] = useState<string>('');
  const [id] = useState<string>(newUniqueId);
  return { text, setText, initialText, setInitialText, id };
}

/**
 * Create a field with state stored as react state hooks
 */
export function useTypedFieldState<T>(
  fieldFns: FieldFns<T>
): TypedFieldState<T> {
  const fs = useFieldState();
  return createTypedFieldState(fieldFns, fs);
}

export function createTypedFieldState<T>(
  fieldFns: FieldFns<T>,
  fs: FieldState
): TypedFieldState<T> {
  return {
    text: fs.text,
    setText: fs.setText,
    isModified: () => fs.text !== fs.initialText,
    isValid: () => fieldFns.validate(fs.text) === null,
    value: () => fieldFns.fromText(fs.text),
    validationError: () => fieldFns.validate(fs.text) || '',
    setValue: (t) => {
      const s = fieldFns.toText(t);
      fs.setText(s);
      fs.setInitialText(s);
    },
    revert: () => fs.setText(fs.initialText),
  };
}

let idCounter = 0;

function newUniqueId(): string {
  idCounter += 1;
  return 'id' + idCounter;
}

/**
 * Stores FieldState explicitly and immutably
 */
export class ImmutableFieldState implements FieldState {
  constructor(
    readonly text: string,
    readonly initialText: string,
    readonly id: string,
    readonly updatefn: (newState: ImmutableFieldState) => void
  ) {}

  setText(s: string) {
    this.updatefn(
      new ImmutableFieldState(s, this.initialText, this.id, this.updatefn)
    );
  }

  setInitialText(s: string) {
    this.updatefn(
      new ImmutableFieldState(this.text, s, this.id, this.updatefn)
    );
  }
}

export function createImmutableFieldState(
  initial: string,
  updatefn: (newState: ImmutableFieldState) => void
): ImmutableFieldState {
  return new ImmutableFieldState(initial, initial, newUniqueId(), updatefn);
}
