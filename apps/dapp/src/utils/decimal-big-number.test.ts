import { BigNumber, ethers } from 'ethers';
import { DecimalBigNumber, DBN_ZERO } from './decimal-big-number';
import { describe, expect, it } from 'vitest';

describe('FixedDecimalBigNumber tests', async () => {
  it('BigNumber reference tests', async () => {
    // For reference, BigNumber.from can only be constructed from int's - not floating point.
    expect(() => BigNumber.from('123.123')).throws(/invalid BigNumber string/);
    expect(BigNumber.from('123').toString()).eq('123');

    // Use ethers parseUnits to convert a floating point into a BigNumber with 18 decimal places.
    const bn = ethers.utils.parseUnits('3.456', 18);
    expect(bn.toString()).eq('3456000000000000000');

    // And you can't have more dp's than specified.
    expect(() => ethers.utils.parseUnits('3.456', 2)).throws(
      /fractional component exceeds decimals/
    );

    // Division on straight bignumber's gives truncated integer results
    // And the decimal places are subtracted: So 18dp-18dp = 0dp
    expect(
      ethers.utils.formatUnits(
        ethers.utils
          .parseUnits('5.246', 18)
          .div(ethers.utils.parseUnits('2.1', 18)),
        0
      )
    ).eq('2');
  });

  it('DBN fromBN & toBN', async () => {
    // Check the constructor, fromBN, toBN line up
    {
      const fpString = '34.567';
      const maxDecimals = 18;
      const bn = ethers.utils.parseUnits(fpString, maxDecimals);
      expect(bn.toString()).eq('34567000000000000000');

      // fromBN & constructor line up
      const dbn: DecimalBigNumber = new DecimalBigNumber(
        bn,
        BigNumber.from(10).pow(maxDecimals)
      );
      const fromBN: DecimalBigNumber = DecimalBigNumber.fromBN(bn, maxDecimals);
      expect(dbn.toBN(maxDecimals).toString()).eq(
        fromBN.toBN(maxDecimals).toString()
      );
      expect(fromBN.toBN(maxDecimals).toString()).eq(bn.toString());
    }

    const checkAsString = (
      fpStringIn: string,
      decimalsIn: number,
      decimalsOut: number,
      bnStringOut: string
    ) => {
      const bnIn = ethers.utils.parseUnits(fpStringIn, decimalsIn);
      const dbn = DecimalBigNumber.fromBN(bnIn, decimalsIn);
      expect(dbn.toBN(decimalsOut).toString()).eq(bnStringOut);
    };

    // Cases
    checkAsString('34.567', 18, 2, '3457'); // Rounds up
    checkAsString('34.565', 18, 2, '3457'); // Rounds up
    checkAsString('34.564', 18, 2, '3456'); // Rounds down
    checkAsString('34.567', 18, 3, '34567'); // No rounding required
    checkAsString('34.567', 18, 10, '345670000000'); // No rounding required
    checkAsString('34.567', 3, 5, '3456700'); // No rounding required
    checkAsString('34.567', 4, 4, '345670'); // No rounding required

    // decimalsIn is less than in the input string
    expect(() => checkAsString('34.567', 2, 3, '34567')).throws(
      /fractional component exceeds decimals/
    );

    // zero should equal...zero.
    expect(DBN_ZERO.toBN(18).toString()).eq('0');
  });

  it('DBN parseUnits', async () => {
    const fpStringIn = '34.567';
    const decimalsIn = 18;
    const dbn1 = DecimalBigNumber.parseUnits(fpStringIn, decimalsIn);

    const bnIn = ethers.utils.parseUnits(fpStringIn, decimalsIn);
    const dbn2 = DecimalBigNumber.fromBN(bnIn, decimalsIn);

    expect(dbn1.toBN(decimalsIn).toString()).eq(
      dbn2.toBN(decimalsIn).toString()
    );
  });

  it('DBN rescaled value', async () => {
    // Use toBN to test the rounding within rescaleValue
    const checkRescaledValue = (
      fpStringIn: string,
      decimalsIn: number,
      decimalsOut: number,
      bnStringOut: string
    ) => {
      const dbn = DecimalBigNumber.parseUnits(fpStringIn, decimalsIn);
      expect(dbn.toBN(decimalsOut).toString()).eq(bnStringOut);
    };

    // No rounding required +ve
    checkRescaledValue('45.1234', 18, 18, '45123400000000000000');
    checkRescaledValue('45.1234', 4, 5, '4512340');
    checkRescaledValue('45.1234', 5, 4, '451234');

    // No rounding required -ve
    checkRescaledValue('-45.1234', 18, 18, '-45123400000000000000');
    checkRescaledValue('-45.1234', 4, 5, '-4512340');
    checkRescaledValue('-45.1234', 5, 4, '-451234');

    // Rounding +ve
    checkRescaledValue('45.1234', 4, 3, '45123'); // Round down
    checkRescaledValue('45.1235', 4, 3, '45124'); // Round up
    checkRescaledValue('45.1236', 4, 3, '45124'); // Round up

    // Rounding -ve
    checkRescaledValue('-45.1234', 4, 3, '-45123'); // Round down
    checkRescaledValue('-45.1235', 4, 3, '-45124'); // Round up
    checkRescaledValue('-45.1236', 4, 3, '-45124'); // Round up

    // Only fractional
    checkRescaledValue('0.1234', 4, 3, '123'); // Round down
    checkRescaledValue('0.1235', 4, 3, '124'); // Round up
    checkRescaledValue('-0.1234', 4, 3, '-123'); // Round down
    checkRescaledValue('-0.1235', 4, 3, '-124'); // Round up

    // 0 dp's in
    checkRescaledValue('45', 0, 3, '45000');
    checkRescaledValue('-45', 0, 3, '-45000');

    // 0 dp's out
    checkRescaledValue('45.1234', 5, 0, '45');
    checkRescaledValue('-45.1234', 5, 0, '-45');

    // Check 0
    checkRescaledValue('0', 5, 6, '0');

    // -ve dp's errors
    expect(() => checkRescaledValue('45.1234', 5, -1, '45')).throws(
      /negative-power/
    );
  });

  it('DBN add', async () => {
    const checkAdd = (
      lhsIn: string,
      lhsDecimals: number,
      rhsIn: string,
      rhsDecimals: number,
      bnStringOut: string,
      decimalsOut: number
    ) => {
      const lhs = DecimalBigNumber.parseUnits(lhsIn, lhsDecimals);
      const rhs = DecimalBigNumber.parseUnits(rhsIn, rhsDecimals);
      const result = lhs.add(rhs);
      expect(result.toBN(decimalsOut).toString()).eq(bnStringOut);
    };

    checkAdd('34.567', 18, '45.1234', 18, '79690400000000000000', 18);

    // rhs dp > lhs dp
    checkAdd('34.567', 3, '45.1234', 5, '79690', 3);
    checkAdd('34.567', 3, '45.1234', 5, '796904', 4);
    checkAdd('34.567', 3, '45.1234', 5, '7969040', 5);
    checkAdd('-134.567', 3, '45.1234', 5, '-8944360', 5);

    // lhs dp > rhs dp
    checkAdd('34.567', 5, '45.1234', 4, '79690', 3);
    checkAdd('34.567', 5, '45.1234', 4, '796904', 4);
    checkAdd('34.567', 5, '45.1234', 4, '7969040', 5);
    checkAdd('-134.567', 5, '45.1234', 4, '-8944360', 5);
  });

  it('DBN sub', async () => {
    const checkSub = (
      lhsIn: string,
      lhsDecimals: number,
      rhsIn: string,
      rhsDecimals: number,
      bnStringOut: string,
      decimalsOut: number
    ) => {
      const lhs = DecimalBigNumber.parseUnits(lhsIn, lhsDecimals);
      const rhs = DecimalBigNumber.parseUnits(rhsIn, rhsDecimals);
      const result = lhs.sub(rhs);
      expect(result.toBN(decimalsOut).toString()).eq(bnStringOut);
    };

    checkSub('34.567', 18, '45.1234', 18, '-10556400000000000000', 18);

    // rhs dp > lhs dp
    checkSub('34.567', 3, '45.1234', 5, '-10556', 3);
    checkSub('34.567', 3, '45.1234', 5, '-105564', 4);
    checkSub('34.567', 3, '45.1234', 5, '-1055640', 5);
    checkSub('-34.567', 3, '45.1234', 5, '-7969040', 5);
    checkSub('45.1234', 4, '-34.567', 5, '7969040', 5);

    // lhs dp > rhs dp
    checkSub('34.567', 5, '45.1234', 4, '-10556', 3);
    checkSub('34.567', 5, '45.1234', 4, '-105564', 4);
    checkSub('34.567', 5, '45.1234', 4, '-1055640', 5);
    checkSub('-34.567', 5, '45.1234', 4, '-7969040', 5);
    checkSub('45.1234', 5, '-34.567', 4, '7969040', 5);
  });

  it('DBN mul', async () => {
    const checkMul = (
      lhsIn: string,
      lhsDecimals: number,
      rhsIn: string,
      rhsDecimals: number,
      bnStringOut: string,
      decimalsOut: number
    ) => {
      const lhs = DecimalBigNumber.parseUnits(lhsIn, lhsDecimals);
      const rhs = DecimalBigNumber.parseUnits(rhsIn, rhsDecimals);
      const result = lhs.mul(rhs);
      expect(result.toBN(decimalsOut).toString()).eq(bnStringOut);
    };

    checkMul('34.567', 18, '45.1234', 18, '1559780567800000000000', 18);
    checkMul('34.567', 3, '45.1234', 4, '1559780567800000000000', 18);
    checkMul('34.567', 3, '45.1234', 4, '1559780568', 6);

    // rhs dp > lhs dp
    checkMul('34.567', 3, '45.1234', 5, '1559781', 3);
    checkMul('34.567', 3, '45.1234', 5, '15597806', 4);
    checkMul('34.567', 3, '45.1234', 5, '15597805678', 7);
    checkMul('-34.567', 3, '45.1234', 5, '-15597805678', 7);
    checkMul('45.1234', 4, '-34.567', 5, '-15597805678', 7);

    // lhs dp > rhs dp
    checkMul('34.567', 5, '45.1234', 4, '1559781', 3);
    checkMul('34.567', 5, '45.1234', 4, '15597806', 4);
    checkMul('34.567', 5, '45.1234', 4, '15597805678', 7);
    checkMul('-34.567', 5, '45.1234', 4, '-15597805678', 7);
    checkMul('45.1234', 5, '-34.567', 4, '-15597805678', 7);
  });

  it('DBN div', async () => {
    const checkDiv = (
      lhsIn: string,
      lhsDecimals: number,
      rhsIn: string,
      rhsDecimals: number,
      bnStringOut: string,
      decimalsOut: number
    ) => {
      const lhs = DecimalBigNumber.parseUnits(lhsIn, lhsDecimals);
      const rhs = DecimalBigNumber.parseUnits(rhsIn, rhsDecimals);
      const result = lhs.div(rhs, decimalsOut);
      expect(result.toBN(decimalsOut).toString()).eq(bnStringOut);
    };

    checkDiv('145.1234', 18, '34.567', 18, '4198322099111869702', 18);
    checkDiv('145.1234', 18, '34.567', 18, '4198322', 6);

    // rhs dp > lhs dp
    checkDiv('141.968662', 6, '34.43', 7, '41234', 4);
    checkDiv('141.968662', 6, '34.43', 7, '4123', 3);
    checkDiv('-141.968662', 6, '34.43', 7, '-41234000', 7);
    checkDiv('141.968662', 6, '-34.43', 7, '-41234000', 7);

    // lhs dp > rhs dp
    checkDiv('141.968662', 6, '34.43', 3, '41234', 4);
    checkDiv('141.968662', 6, '34.43', 3, '4123', 3);
    checkDiv('-141.968662', 6, '34.43', 3, '-41234000', 7);
    checkDiv('141.968662', 6, '-34.43', 3, '-41234000', 7);

    // Throws for div by zero
    expect(() => checkDiv('141.968662', 6, '0', 7, '0', 7)).throws(
      /division-by-zero/
    );
    expect(() => checkDiv('141.968662', 6, '-0', 7, '0', 7)).throws(
      /division-by-zero/
    );

    // Divide by 1
    checkDiv('176.398662', 6, '1', 3, '176398662', 6);
    checkDiv('176.398662', 6, '-1.00', 3, '-176398662', 6);

    // Rounding +ve
    checkDiv('176.398662', 6, '34.43', 3, '5123', 3); // Round down 5.1234 -> 5.123
    checkDiv('176.402105', 6, '34.43', 3, '5124', 3); // Round up 5.1235 -> 5.124
    checkDiv('176.405548', 6, '34.43', 3, '5124', 3); // Round up 5.1236 -> 5.124

    // 0 dp's in
    checkDiv('275', 0, '5.546', 3, '4959', 2); // Round up 49.5852 -> 49.59
    checkDiv('275', 0, '5.544', 3, '4960', 2); // Round down 49.6031 -> 49.60

    // 0 dp's out
    checkDiv('68.511', 3, '12.3', 2, '6', 0); // Round up 5.57 -> 6
    checkDiv('66.42', 3, '12.3', 2, '5', 0); // Round up 5.4 -> 5

    // Rounding -ve
    checkDiv('176.398662', 6, '-34.43', 3, '-5123', 3); // Round down 5.1234 -> 5.123
    checkDiv('176.402105', 6, '-34.43', 3, '-5124', 3); // Round up 5.1235 -> 5.124
    checkDiv('176.405548', 6, '-34.43', 3, '-5124', 3); // Round up 5.1236 -> 5.124

    // 0 dp's in
    checkDiv('275', 0, '-5.546', 3, '-4959', 2); // Round up -49.5852 -> -49.59
    checkDiv('-275', 0, '5.544', 3, '-4960', 2); // Round down -49.6031 -> -49.60

    // 0 dp's out
    checkDiv('-68.511', 3, '12.3', 2, '-6', 0); // Round up -5.57 -> -6
    checkDiv('66.42', 3, '-12.3', 2, '-5', 0); // Round up -5.4 -> -5

    // Check 0
    checkDiv('0', 0, '34.43', 3, '0', 0);
    checkDiv('-0', 0, '34.43', 3, '0', 0);
  });

  it('DBN comparisons', async () => {
    const checkComparison = (
      op: (other: DecimalBigNumber) => boolean,
      lhsIn: string,
      lhsDecimals: number,
      rhsIn: string,
      rhsDecimals: number,
      expected: boolean
    ) => {
      const lhs = DecimalBigNumber.parseUnits(lhsIn, lhsDecimals);
      const rhs = DecimalBigNumber.parseUnits(rhsIn, rhsDecimals);
      const result = op.call(lhs, rhs);
      expect(result).eq(expected);
    };

    // lt
    checkComparison(
      DecimalBigNumber.prototype.lt,
      '176.398661',
      6,
      '176.398662',
      6,
      true
    );
    checkComparison(
      DecimalBigNumber.prototype.lt,
      '176.398662',
      6,
      '176.398662',
      6,
      false
    );
    checkComparison(
      DecimalBigNumber.prototype.lt,
      '176.398663',
      6,
      '176.398662',
      6,
      false
    );

    checkComparison(
      DecimalBigNumber.prototype.lt,
      '176.398661',
      6,
      '176.398662',
      9,
      true
    );
    checkComparison(
      DecimalBigNumber.prototype.lt,
      '176.398662',
      6,
      '176.398662',
      9,
      false
    );
    checkComparison(
      DecimalBigNumber.prototype.lt,
      '176.398663',
      6,
      '176.398662',
      9,
      false
    );

    checkComparison(
      DecimalBigNumber.prototype.lt,
      '-176.398661',
      6,
      '-176.398662',
      9,
      false
    );
    checkComparison(
      DecimalBigNumber.prototype.lt,
      '-176.398662',
      6,
      '-176.398662',
      9,
      false
    );
    checkComparison(
      DecimalBigNumber.prototype.lt,
      '-176.398663',
      6,
      '-176.398662',
      9,
      true
    );

    // lte
    checkComparison(
      DecimalBigNumber.prototype.lte,
      '176.398661',
      6,
      '176.398662',
      6,
      true
    );
    checkComparison(
      DecimalBigNumber.prototype.lte,
      '176.398662',
      6,
      '176.398662',
      6,
      true
    );
    checkComparison(
      DecimalBigNumber.prototype.lte,
      '176.398663',
      6,
      '176.398662',
      6,
      false
    );

    checkComparison(
      DecimalBigNumber.prototype.lte,
      '176.398661',
      6,
      '176.398662',
      9,
      true
    );
    checkComparison(
      DecimalBigNumber.prototype.lte,
      '176.398662',
      6,
      '176.398662',
      9,
      true
    );
    checkComparison(
      DecimalBigNumber.prototype.lte,
      '176.398663',
      6,
      '176.398662',
      9,
      false
    );

    checkComparison(
      DecimalBigNumber.prototype.lte,
      '-176.398661',
      6,
      '-176.398662',
      9,
      false
    );
    checkComparison(
      DecimalBigNumber.prototype.lte,
      '-176.398662',
      6,
      '-176.398662',
      9,
      true
    );
    checkComparison(
      DecimalBigNumber.prototype.lte,
      '-176.398663',
      6,
      '-176.398662',
      9,
      true
    );

    // gt
    checkComparison(
      DecimalBigNumber.prototype.gt,
      '176.398661',
      6,
      '176.398662',
      6,
      false
    );
    checkComparison(
      DecimalBigNumber.prototype.gt,
      '176.398662',
      6,
      '176.398662',
      6,
      false
    );
    checkComparison(
      DecimalBigNumber.prototype.gt,
      '176.398663',
      6,
      '176.398662',
      6,
      true
    );

    checkComparison(
      DecimalBigNumber.prototype.gt,
      '176.398661',
      6,
      '176.398662',
      9,
      false
    );
    checkComparison(
      DecimalBigNumber.prototype.gt,
      '176.398662',
      6,
      '176.398662',
      9,
      false
    );
    checkComparison(
      DecimalBigNumber.prototype.gt,
      '176.398663',
      6,
      '176.398662',
      9,
      true
    );

    checkComparison(
      DecimalBigNumber.prototype.gt,
      '-176.398661',
      6,
      '-176.398662',
      9,
      true
    );
    checkComparison(
      DecimalBigNumber.prototype.gt,
      '-176.398662',
      6,
      '-176.398662',
      9,
      false
    );
    checkComparison(
      DecimalBigNumber.prototype.gt,
      '-176.398663',
      6,
      '-176.398662',
      9,
      false
    );
  });

  it('DBN min', async () => {
    const checkMin = (
      lhsIn: string,
      lhsDecimals: number,
      rhsIn: string,
      rhsDecimals: number,
      bnStringOut: string,
      decimalsOut: number
    ) => {
      const lhs = DecimalBigNumber.parseUnits(lhsIn, lhsDecimals);
      const rhs = DecimalBigNumber.parseUnits(rhsIn, rhsDecimals);
      const result = lhs.min(rhs);
      expect(result.toBN(decimalsOut).toString()).eq(bnStringOut);
    };

    checkMin('176.398661', 6, '176.398662', 6, '176398661', 6);
    checkMin('176.398662', 6, '176.398662', 6, '176398662', 6);
    checkMin('176.398663', 6, '176.398662', 6, '176398662', 6);

    checkMin('176.398661', 6, '176.398662', 9, '176398661', 6);
    checkMin('176.398662', 6, '176.398662', 9, '176398662', 6);
    checkMin('176.398663', 6, '176.398662', 9, '176398662000', 9);

    checkMin('-176.398661', 6, '-176.398662', 9, '-176398662000', 9);
    checkMin('-176.398662', 6, '-176.398662', 9, '-176398662', 6);
    checkMin('-176.398663', 6, '-176.398662', 9, '-176398663', 6);
  });
});
