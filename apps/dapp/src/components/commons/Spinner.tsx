import type { FC } from 'react';

import styled from 'styled-components';
import { rotateKeyframes } from '@/styles/mixins/rotate-keyframes';

type Size = 'small' | 'medium' | 'large';

type SpinnerProps = {
  customSize?: number;
  size?: Size;
};

const SIZES: { [Key in Size]: number } = {
  small: 20,
  medium: 40,
  large: 200,
};

const StyledDiv = styled.div<{ size: number }>`
  border-radius: 100%;
  width: ${({ size }) => size}px;
  height: ${({ size }) => size}px;
  box-sizing: border-box;
  border: ${({ size }) => size / 10}px solid;
  border-color: #e0e0e0;
  border-right-color: #616161;
  animation: ${rotateKeyframes} 0.65s linear infinite;
`;

export const Spinner: FC<SpinnerProps> = ({ size = 'small', customSize }) => (
  <StyledDiv size={customSize ?? SIZES[size]} />
);
