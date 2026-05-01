import z from "zod";

export class FetchError extends Error {
  constructor(
    readonly httpStatus: number,
    message: string
  ) {
    super(message);
  }
}

const addressRegex = /^0x[a-fA-F0-9]{40}$/;
const hexRegex = /^0x(?:[a-fA-F0-9]{2})*$/;

export function isAddress(
  address: string,
) {
  const result = (() => {
    if (!addressRegex.test(address)) return false
    if (address.toLowerCase() === address) return true
    return true
  })()
  return result
}

export const AddressSchema = z
  .string()
  .refine(
    (value): value is `0x${string}` => isAddress(value),
    {
      message:
        'Invalid Ethereum address format - must start with 0x and be followed by 40 hexadecimal characters (checksum not enforced)',
    }
  );
export type AddressSchemaType = z.infer<typeof AddressSchema>;

export const HexSchema = z
  .string()
  .refine((value): value is `0x${string}` => hexRegex.test(value), {
    message:
      'Invalid Ethereum hex format - must start with 0x and have an even number of hexadecimal characters',
  });
export type HexSchemaType = z.infer<typeof HexSchema>;

export const BigIntSchema = z
  .string()
  .refine((value): value is `${number}` => /^[0-9]+$/.test(value), {
    message: 'Invalid BigInt string — must contain only digits 0–9',
  })
  .transform((value) => BigInt(value));

export type BigIntSchemaType = z.infer<typeof BigIntSchema>;
