import { DecimalBigNumber } from './decimal-big-number';

export const formatNumber = (number: number): string => {
  const stringified = number.toString();
  const decimalPlaces = stringified.includes('.')
    ? stringified.split('.')[1].length
    : 0;

  const localeFormatted =
    decimalPlaces > 3
      ? number.toLocaleString('en-US', {
          minimumFractionDigits: 4,
        })
      : number.toLocaleString('en-US');

  const thousandsSeparatorCount = localeFormatted.split(',').length - 1;
  const shortenedString = localeFormatted.slice(0, 5);

  if (thousandsSeparatorCount > 0) {
    return (
      shortenedString.replace(',', '.') +
      ` ${thousandsSeparatorCount > 1 ? 'M' : 'k'}`
    );
  } else {
    return shortenedString;
  }
};

export function formatPercent(number: number): string {
  return formatNumber(number * 100);
}

export const formatDecimalBigNumber = (dbn: DecimalBigNumber): string => {
  // Rebased to 4 decimal places (which rounds), since that's the most formatNumber() shows.
  return formatNumber(Number(dbn.formatUnits(4)));
};
