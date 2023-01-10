// A record specifying operations on a text field:
//
//    toText   : convert a js value to the text content
//    validate : validate the text content returning a validate
//               error message on failure, or null on success
//    fromText : convert the text content back into a js value
//    equals   : compare two js values for this field

export interface FieldFns<T> {
  toText(value: T): string;
  validate(text: string): null | string;
  fromText(text: string): T;
  equals(v1: T, v2: T): boolean;
  datalist?: string[];
}

// Add a datalist (ie list of precanned values) to a field
export function withDatalist<T>(
  fieldFns: FieldFns<T>,
  datalist: string[]
): FieldFns<T | null> {
  const newFieldFns = { ...fieldFns };
  newFieldFns.datalist = datalist;
  return newFieldFns;
}
