import { CSSProperties } from 'react';
import { Link as RRLink } from 'react-router-dom';
import styled from 'styled-components';

export interface LinkProps {
  href: string;
  children?: React.ReactNode;
  removedecoration?: boolean;
  style?: CSSProperties;
}

const RRLinkStyled = styled(RRLink)`
  color: ${({ theme }) => theme.colors.greyMid};
  font-size: 0.9rem;
  font-weight: bold;
  text-decoration: underline;
  filter: brightness(1.3);
  transition: color 300ms ease;
  &:hover {
    color: ${({ theme }) => theme.colors.white};
  }
`;

const RRLinkStyledUndecorated = styled(RRLink)`
  text-decoration: none;
`;

export function Link(props: LinkProps) {
  return props.removedecoration ? (
    <RRLinkStyledUndecorated to={props.href}>
      {props.children}
    </RRLinkStyledUndecorated>
  ) : (
    <RRLinkStyled to={props.href} style={props.style}>
      {props.children}
    </RRLinkStyled>
  );
}
