import { useMediaQuery } from '@/hooks/use-media-query';
import breakpoints from '@/styles/responsive-breakpoints';
import { theme } from '@/styles/theme';
import { useState } from 'react';
import { useLocation } from 'react-router-dom';
import styled from 'styled-components';
import { ConnectWalletButton } from '../commons/ConnectWalletButton';
import { Icon } from '../commons/Icon';
import { RightPanelOverlay } from '../commons/RightPanelOverlay';
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
  const isDesktop = useMediaQuery(theme.responsiveBreakpoints.md);
  const [panelOpen, setPanelOpen] = useState(false);

  const MenuItems = () => {
    return (
      <StyledNav>
        <Title>NAVIGATION</Title>
        {navLinkProps.map((linkProps) => (
          <>
            <NavLink
              key={linkProps.label}
              currentRoute={location.pathname}
              {...linkProps}
              onClick={() => setPanelOpen(false)}
            />
            <HR key={`hr_${linkProps.label}`} />
          </>
        ))}
        <ConnectWalletButton />
      </StyledNav>
    );
  };

  if (isDesktop) return <MenuItems />;

  return (
    <>
      <HamburgerIcon iconName="settings" onClick={() => setPanelOpen(true)} />
      {panelOpen && (
        <RightPanelOverlay
          Content={() => <MenuItems />}
          hidePanel={() => setPanelOpen(false)}
        />
      )}
    </>
  );
};

const Title = styled.h1`
  ${breakpoints.md(`
    display: none;
  `)}
`;
const StyledNav = styled.nav`
  box-sizing: border-box;
  display: flex;
  margin: 2rem;
  flex-direction: column;
  justify-content: center;
  gap: 2rem;

  ${breakpoints.md(`
    margin: 0;
    align-items: center;
    width: fit-content;
    flex-direction: row;
  `)}
`;

const HamburgerIcon = styled(Icon)`
  cursor: pointer;
  transition: all 300ms ease;
  &:hover {
    filter: contrast(1000%);
  }
`;

const HR = styled.hr`
  width: 80%;
  border: none;
  height: 1px;
  margin: 0px;
  background-color: ${({ theme }) => theme.colors.greyDark};

  ${breakpoints.md(`
    display: none;
  `)}
`;
