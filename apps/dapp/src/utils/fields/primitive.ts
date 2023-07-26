import { FieldFns } from './type';

// A string field

export const stringFieldFns: FieldFns<string> = {
  toText(v) {
    return v;
  },
  validate(_text) {
    return null;
  },
  fromText(text) {
    return text;
  },
  equals(v1, v2) {
    return v1 === v2;
  },
};

export const STRING_FIELD: FieldFns<string> = stringFieldFns;

// A string field constrained by a regex
//
// If the regex contains capture groups, the field result will be the value
// of the first capture group. Otherwise the field result will be the
// whole matching string. Hence a capture group can be used to allow preceding/trailing
// whitespace in a field, but to exclude it from the result.
export function regexStringFieldFns(
  regex: string,
  description: string,
  returnGroup: number
): FieldFns<string> {
  const re = new RegExp(regex);
  return {
    toText(v) {
      return v;
    },
    validate(text) {
      const match = text.match(re);
      if (match) {
        return null;
      } else {
        return 'must be ' + description;
      }
    },
    fromText(text) {
      const match = text.match(re);
      if (match && match.length > 1) {
        return match[returnGroup];
      }
      return text;
    },
    equals(v1, v2) {
      return v1 === v2;
    },
  };
}

// A string field that can't be empty

export const NON_EMPTY_STRING_FIELD: FieldFns<string> = regexStringFieldFns(
  '^.+$',
  'non-empty',
  0
);

// A bounded integer field

export function intFieldFns(
  minValue: number | null,
  maxValue: number | null
): FieldFns<number> {
  return {
    toText(v) {
      return '' + v;
    },
    validate(text) {
      const v = parseInt(text, 10);
      if (isNaN(v)) {
        return 'must be an integer';
      } else if (minValue !== null && v < minValue) {
        return 'value too small';
      } else if (maxValue !== null && v > maxValue) {
        return 'value too large';
      } else {
        return null;
      }
    },
    fromText(text) {
      return parseInt(text, 10);
    },
    equals(v1, v2) {
      return v1 === v2;
    },
  };
}

// An arbitrary number
export function numberFieldFns(): FieldFns<number> {
  return {
    toText(v) {
      return '' + v;
    },
    validate(text) {
      const v = parseFloat(text);
      if (isNaN(v)) {
        return 'must be a number';
      } else {
        return null;
      }
    },
    fromText(text) {
      return parseFloat(text);
    },
    equals(v1, v2) {
      return v1 === v2;
    },
  };
}

export const NUMBER_FIELD: FieldFns<number> = numberFieldFns();

// A BigDecimal field, which is stored as a string
// but must be validated as a number
export function bigDecimalFieldFns(): FieldFns<string> {
  return regexStringFieldFns(
    '^\\s*(-?(?:\\d+(?:\\.\\d+)?|\\.\\d+))\\s*$',
    'a decimal value',
    1
  );
}

export const BIG_DECIMAL_STRING_FIELD: FieldFns<string> = bigDecimalFieldFns();

// A boolean field

export function boolFieldFns(): FieldFns<boolean> {
  return {
    toText(v: boolean) {
      return v ? 'true' : 'false';
    },
    validate(text: string): string | null {
      const ltext = text.toLowerCase();
      if (
        ltext.length > 0 &&
        ('true'.startsWith(ltext) || 'false'.startsWith(ltext))
      ) {
        return null;
      }
      return 'Bool must be true or false';
    },
    fromText(text) {
      const ltext = text.toLowerCase();
      return 'true'.startsWith(ltext);
    },
    equals(v1, v2) {
      return v1 === v2;
    },
  };
}

export const BOOLEAN_FIELD: FieldFns<boolean> = boolFieldFns();

// A Json field

export function jsonFieldFns(): FieldFns<unknown> {
  return {
    toText(v: unknown): string {
      return JSON.stringify(v, null, 2);
    },
    validate(text: string): string | null {
      try {
        JSON.parse(text);
      } catch (e) {
        return 'Json is not well formed';
      }
      return null;
    },
    fromText(text: string): unknown {
      return JSON.parse(text);
    },
    equals(v1, v2) {
      return JSON.stringify(v1) === JSON.stringify(v2);
    },
  };
}

export const JSON_FIELD: FieldFns<unknown> = jsonFieldFns();

// An email address field
// See  https://stackoverflow.com/questions/201323/how-to-validate-an-email-address-using-a-regular-expression
export const EMAIL_FIELD: FieldFns<string> = regexStringFieldFns(
  '^\\s*((?:[a-z0-9!#$%&\'*+/=?^_`{|}~-]+(?:\\.[a-z0-9!#$%&\'*+/=?^_`{|}~-]+)*|"(?:[\\x01-\\x08\\x0b\\x0c\\x0e-\\x1f\\x21\\x23-\\x5b\\x5d-\\x7f]|\\\\[\\x01-\\x09\\x0b\\x0c\\x0e-\\x7f])*")@(?:(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\\.)+[a-z0-9](?:[a-z0-9-]*[a-z0-9])?|\\[(?:(?:(2(5[0-5]|[0-4][0-9])|1[0-9][0-9]|[1-9]?[0-9]))\\.){3}(?:(2(5[0-5]|[0-4][0-9])|1[0-9][0-9]|[1-9]?[0-9])|[a-z0-9-]*[a-z0-9]:(?:[\\x01-\\x08\\x0b\\x0c\\x0e-\\x1f\\x21-\\x5a\\x53-\\x7f]|\\\\[\\x01-\\x09\\x0b\\x0c\\x0e-\\x7f])+)\\]))\\s*$',
  'an email address',
  1
);

interface Mapping<T> {
  value: T;
  label: string;
}

// A custom field for a finite set of values of type t, labeled by strings

export function labelledValuesFieldFns<T>(
  typelabel: string,
  equals: (v1: T, v2: T) => boolean,
  mappings: Mapping<T>[]
): FieldFns<T> {
  const labelmap: { [key: string]: T } = {};
  mappings.forEach((m) => {
    labelmap[m.label] = m.value;
  });
  const datalist = mappings.map((m) => m.label);

  function toText(value: T): string {
    for (const m of mappings) {
      if (equals(m.value, value)) {
        return m.label;
      }
    }
    // If we can't find a mapping, use the underlying value with ":" as a
    // marker prefix
    return ':' + String(value);
  }

  function validate(text: string): null | string {
    if (Object.prototype.hasOwnProperty.call(labelmap, text)) {
      return null;
    }
    return 'must be a ' + typelabel;
  }

  function fromText(text: string): T {
    return labelmap[text];
  }

  return {
    toText,
    validate,
    fromText,
    equals,
    datalist,
  };
}
