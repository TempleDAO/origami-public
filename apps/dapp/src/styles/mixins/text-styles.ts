import { css } from 'styled-components';
import breakpoints from '../responsive-breakpoints';

// Text styles as specified in the figma designs

export const textH1 = css`
  font-weight: bold;
  font-size: 1.25rem;

  ${breakpoints.md(`
    font-size: 1.75rem;
  `)}
`;

export const textH2 = css`
  font-weight: bold;
  font-size: 1.125rem;

  ${breakpoints.md(`
    font-size: 1.5rem;
  `)}
`;

export const textH3 = css`
  font-weight: bold;

  ${breakpoints.md(`
    font-weight: bold;
    font-size: 1.125rem;
  `)}
`;

export const textH4 = css`
  font-weight: bold;
  font-size: 0.875rem;

  ${breakpoints.md(`
    font-size: 1.125rem;
  `)}
`;

export const textH5 = css`
  font-size: 0.75rem;

  ${breakpoints.md(`
    font-size: 1rem;
  `)}
`;

export const textP1 = css`
  font-size: 0.875rem;

  ${breakpoints.md(`
    font-size: 1rem;
  `)}
`;

export const textP2 = css`
  font-size: 0.75rem;

  ${breakpoints.md(`
    font-size: 0.875rem;
  `)}
`;

export const textPrimaryGradient = css`
  background: ${({ theme }) => theme.colors.gradients.primary};
  background-clip: text;
  -webkit-background-clip: text;
  text-fill-color: transparent;
  -webkit-text-fill-color: transparent;
`;

export const textUnderlinePrimaryGradient = css`
  position: relative;
  &:before {
    content: '';
    position: absolute;
    top: 1.3rem;
    width: 100%;
    left: 0;
    height: 1px;
    background: ${({ theme }) => theme.colors.gradients.primary};
  }
`;
