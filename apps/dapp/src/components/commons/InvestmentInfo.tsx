import styled from 'styled-components';
import breakpoints from '@/styles/responsive-breakpoints';
import ReactMarkdown from 'react-markdown';

export const InvestmentInfo = styled(ReactMarkdown)`
  color: ${({ theme }) => theme.colors.greyLight};
  font-size: 0.875rem;

  ${breakpoints.md(`
    font-size: 1rem;
  `)}

  p {
    margin-top: 0;
  }

  a {
    color: ${({ theme }) => theme.colors.white};
    transition: 300ms ease color;
    &:hover {
      color: ${({ theme }) => theme.colors.greyLight};
    }
    cursor: pointer;
    text-decoration-line: underline;
  }
`;
