import { css } from 'styled-components';

export const tabActiveGradientStyles = css`
  border-bottom-width: 0.125rem;
  border-bottom-style: solid;
  border-image-slice: 1;
  border-image-source: ${({ theme }) => theme.colors.gradients.primary};
`;
