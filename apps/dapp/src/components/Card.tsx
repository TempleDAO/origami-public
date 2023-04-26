import styled, { keyframes } from 'styled-components';
import sunkenStyles from '@/styles/mixins/cards/sunken';
import { css } from 'styled-components';
import breakpoints from '@/styles/responsive-breakpoints';
import { textH3, textH5 } from '@/styles/mixins/text-styles';
import { tabActiveGradientStyles } from '@/styles/mixins/tab-styles';

export const Card = styled.div<{ isExpanded: boolean }>`
  display: grid;
  padding: 1.5rem;
  border-radius: 2.5rem;
  background-color: ${({ theme }) => theme.colors.bgMid};
  ${sunkenStyles};

  ${({ isExpanded }) =>
    isExpanded &&
    css`
      animation: ${expandingKeyframes} 0.2s linear;
    `}
`;

export const CardContent = styled.div`
  display: grid;
  row-gap: 1rem;
  grid-template-columns: 1fr 1fr 1fr 1fr;
  ${breakpoints.lg(`
    grid-template-columns: 6fr 1fr 1fr 1fr 1fr 2fr;
  `)}
`;

export const CardHeader = styled.div`
  display: flex;
  flex-direction: row;
  justify-content: space-between;
  margin-bottom: 16;
  cursor: pointer;
`;

export const CardColumn = styled.section`
  margin: 1rem 0;
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
`;

const expandingKeyframes = keyframes`
  0% {
    height: 0;
    transition: height 0.5s;
    overflow: hidden;
  }

  100% {
    height: 300px;
    transition: height 0.5s;
    overflow: hidden;
  }
`;

export const GridValue = styled.div<{
  active?: boolean;
  subdued?: boolean;
}>`
  ${textH3};
  display: flex;
  align-items: flex-start;
  justify-content: center;
  text-align: center;
  color: ${({ subdued, theme }) =>
    subdued ? theme.colors.greyLight : theme.colors.white};
  border-bottom: 0.125rem solid transparent;
  ${({ active }) => active && tabActiveGradientStyles};
  transition: 300ms ease color;
  cursor: ${({ onClick }) => onClick && 'pointer'};

  ${breakpoints.lg(`
    min-height: unset;
  `)}

  &:hover {
    color: ${({ theme }) => theme.colors.greyLight};
  }
`;

export const SuffixSpan = styled.span`
  ${textH5};
  color: ${({ theme }) => theme.colors.greyLight};
`;
