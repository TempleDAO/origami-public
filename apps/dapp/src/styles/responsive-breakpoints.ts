import { css } from 'styled-components';

export const smOnly = (styles: string) => {
  return css`
    @media (max-width: ${({ theme }) => theme.responsiveBreakpoints.md}) {
      ${styles}
    }
  `;
};

export const sm = (styles: string) => {
  return css`
    @media screen and (min-width: ${({ theme }) =>
        theme.responsiveBreakpoints.sm}) {
      ${styles}
    }
  `;
};

export const md = (styles: string) => {
  return css`
    @media screen and (min-width: ${({ theme }) =>
        theme.responsiveBreakpoints.md}) {
      ${styles}
    }
  `;
};

export const lg = (styles: string) => {
  return css`
    @media screen and (min-width: ${({ theme }) =>
        theme.responsiveBreakpoints.lg}) {
      ${styles}
    }
  `;
};

export const xl = (styles: string) => {
  return css`
    @media screen and (min-width: ${({ theme }) =>
        theme.responsiveBreakpoints.xl}) {
      ${styles}
    }
  `;
};

export const xxl = (styles: string) => {
  return css`
    @media screen and (min-width: ${({ theme }) =>
        theme.responsiveBreakpoints.xxl}) {
      ${styles}
    }
  `;
};

export const min = (size: number, styles: string) => {
  return css`
    @media screen and (min-width: ${size}px) {
      ${styles}
    }
  `;
};

export const max = (size: number, styles: string) => {
  return css`
    @media screen and (max-width: ${size}px) {
      ${styles}
    }
  `;
};

const breakpoints = {
  smOnly,
  sm,
  md,
  lg,
  xl,
  xxl,
  min,
  max,
};

export default breakpoints;
