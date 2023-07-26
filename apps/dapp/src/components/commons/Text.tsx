import styled from 'styled-components';
import breakpoints from '@/styles/responsive-breakpoints';

export const Text = styled.p<{ small?: boolean }>`
  margin: 0;
  font-size: ${({ small }) => (small ? 0.75 : 0.875)}rem;

  ${({ small }) =>
    breakpoints.md(`
        font-size: ${small ? 0.875 : 1}rem;
    `)}
`;
