import { useLocation } from 'react-router-dom';
import styled from 'styled-components';
import { NavLink } from './NavLink';

const navLinkProps = [
  {
    label: 'INVEST',
    href: '/invest',
    routes: ['/invest'],
  },
  { label: 'MANAGE', href: '/manage', routes: ['/manage'] },
];

export const Navigation = () => {
  const location = useLocation();

  return (
    <StyledNav>
      {navLinkProps.map((linkProps) => (
        <NavLink
          key={linkProps.label}
          currentRoute={location.pathname}
          {...linkProps}
        />
      ))}
    </StyledNav>
  );
};

const StyledNav = styled.nav`
  display: flex;
  gap: 2rem;
`;
