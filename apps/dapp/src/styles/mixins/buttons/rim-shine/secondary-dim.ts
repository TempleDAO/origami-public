import { css } from 'styled-components';

const rimShineSecondaryDim = css`
  border: 2px transparent;
  padding: 2px;
  background-image: ${({ theme }) => `linear-gradient(
      ${theme.colors.bgDark},
      ${theme.colors.bgDark}
    )`},
    linear-gradient(
      180deg,
      rgba(255, 255, 255, 0.1) 0%,
      rgba(255, 255, 255, 0) 100%
    );
  background-origin: border-box;
  background-clip: content-box, border-box;
`;

export const customColorRimShineSecondaryDim = (color: string) => css`
  border: 2px transparent;
  padding: 2px;
  background-image: linear-gradient(${color}, ${color}),
    linear-gradient(
      180deg,
      rgba(255, 255, 255, 0.1) 0%,
      rgba(255, 255, 255, 0) 100%
    );
  background-origin: border-box;
  background-clip: content-box, border-box;
`;

export default rimShineSecondaryDim;
