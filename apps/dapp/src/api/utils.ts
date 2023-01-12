import { ethers } from 'ethers';
import { TypedEventFilter, TypedEvent } from '@/typechain/common';

/**
 * Finds the events that match the specified address and filter, and
 * returns these parsed and mapped to the appropriate type
 */
export function matchEvents<TArgsArray extends unknown[], TArgsObject>(
  events: ethers.Event[],
  contract: ethers.BaseContract,
  address: string | undefined,
  eventFilter: TypedEventFilter<TypedEvent<TArgsArray, TArgsObject>>
): TypedEvent<TArgsArray, TArgsObject>[] {
  return events
    .filter((ev) => !address || address === ev.address)
    .filter((ev) => matchTopics(eventFilter.topics, ev.topics))
    .map((ev) => {
      const args = contract.interface.parseLog(ev).args;
      const result: TypedEvent<TArgsArray, TArgsObject> = {
        ...ev,
        args: args as TArgsArray & TArgsObject,
      };
      return result;
    });
}

function matchTopics(
  filter: Array<string | Array<string>> | undefined,
  value: Array<string>
): boolean {
  // Implement the logic for topic filtering as described here:
  // https://docs.ethers.io/v5/concepts/events/#events--filters
  if (!filter) {
    return false;
  }
  for (let i = 0; i < filter.length; i++) {
    const f = filter[i];
    const v = value[i];
    if (typeof f == 'string') {
      if (f !== v) {
        return false;
      }
    } else {
      if (f.indexOf(v) === -1) {
        return false;
      }
    }
  }
  return true;
}

export function first<T>(values: T[]): T | undefined {
  return values.length >= 1 ? values[0] : undefined;
}
