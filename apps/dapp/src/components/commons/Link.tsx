import { Link as RRLink } from 'react-router-dom';
import styled from 'styled-components';

export interface LinkProps {
  href: string;
  children?: React.ReactNode;
  removedecoration?: boolean;
}

const RRLinkStyled = styled(RRLink)``;

const RRLinkStyledUndecorated = styled(RRLink)`
  text-decoration: none;
`;

export function Link(props: LinkProps) {
  return props.removedecoration ? (
    <RRLinkStyledUndecorated to={props.href}>
      {props.children}
    </RRLinkStyledUndecorated>
  ) : (
    <RRLinkStyled to={props.href}>{props.children}</RRLinkStyled>
  );
}
