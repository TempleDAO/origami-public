import type { GasPriorityFee } from '@/api/types';

import React, { useState } from 'react';
import styled from 'styled-components';
import {
  LabelledValue,
  SmallSelection,
} from '@/components/commons/SmallSelection';
import { Icon } from '@/components/commons/Icon';
import { textP1 } from '@/styles/mixins/text-styles';

export interface AdvancedOptionsProps {
  slippageTolerance: number;
  gasPriorityFee: GasPriorityFee;

  setSlippageTolerance(v: number): void;
  setGasPriorityFee(v: GasPriorityFee): void;
}

export const SLIPPAGE_TOLERANCE_VALUES: LabelledValue<number>[] = [
  ['0.1%', 0.001],
  ['0.5%', 0.005],
  ['1%', 0.01],
  ['1.5%', 0.015],
];

export const GAS_FEE_VALUES: LabelledValue<GasPriorityFee>[] = [
  ['Slow', 'slow'],
  ['Standard', 'standard'],
  ['Fast', 'fast'],
];

export function AdvancedOptions(props: AdvancedOptionsProps) {
  const [expanded, setExpanded] = useState<boolean>(false);

  return (
    <FlexDown>
      <TitleContainer onClick={() => setExpanded((e) => !e)}>
        <Title>Advanced Options</Title>
        <StyledIcon iconName={'expand-light'} expanded={expanded} size={12} />
      </TitleContainer>

      {expanded && (
        <Indent>
          <FlexRight>
            <Label>Slippage Tolerance</Label>
            <SmallSelection
              value={props.slippageTolerance}
              values={SLIPPAGE_TOLERANCE_VALUES}
              onChange={props.setSlippageTolerance}
            />
          </FlexRight>

          <FlexRight>
            <Label>Gas priority fee</Label>
            <SmallSelection
              value={props.gasPriorityFee}
              values={GAS_FEE_VALUES}
              onChange={props.setGasPriorityFee}
            />
          </FlexRight>
        </Indent>
      )}
    </FlexDown>
  );
}

export interface AdvancedOptionsState {
  slippageTolerance: number;
  gasPriorityFee: GasPriorityFee;

  setSlippageTolerance(v: number): void;
  setGasPriorityFee(v: GasPriorityFee): void;
}

export function useAdvancedOptionsState() {
  const [slippageTolerance, setSlippageTolerance] = useState<number>(
    SLIPPAGE_TOLERANCE_VALUES[1][1]
  );
  const [gasPriorityFee, setGasPriorityFee] = useState<GasPriorityFee>(
    GAS_FEE_VALUES[1][1]
  );

  return {
    slippageTolerance,
    setSlippageTolerance,
    gasPriorityFee,
    setGasPriorityFee,
  };
}

const Title = styled.span`
  ${textP1}
  color: ${({ theme }) => theme.colors.white};
  transition: 300ms ease color;
`;

const Indent = styled.div`
  margin-left: 10px;
`;

const Label = styled.span`
  color: ${({ theme }) => theme.colors.white};
`;

const TitleContainer = styled.div`
  display: flex;
  flex-direction: row;
  justify-content: center;
  justify-content: space-between;
  cursor: pointer;
  &:hover {
    span {
      color: ${({ theme }) => theme.colors.greyLight};
    }
  }
`;

const FlexDown = styled.div`
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
`;

const FlexRight = styled.div`
  display: flex;
  flex-direction: row;
  justify-content: space-between;
  &:not(:last-of-type) {
    margin-bottom: 0.5rem;
  }
`;

const StyledIcon = styled(Icon)<{ expanded?: boolean }>`
  ${({ expanded }) => expanded && `rotate: 180deg;`}
`;
