import styled from 'styled-components';
import breakpoints from '@/styles/responsive-breakpoints';
import ReactMarkdown from 'react-markdown';

const NewTabLinkRenderer = (
  props: React.AnchorHTMLAttributes<HTMLAnchorElement>
) => (
  <a href={props.href} target="_blank" rel="noopener noreferrer">
    {props.children}
  </a>
);

export const InvestmentInfo = styled(ReactMarkdown).attrs({
  components: { a: NewTabLinkRenderer },
})`
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
