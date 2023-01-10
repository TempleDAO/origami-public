import type { Layout } from '@/components/Layouts/types';

import styled from 'styled-components';
import { Header } from '@/components/Header';
import { Footer } from '@/components/Footer';
import breakpoints from '@/styles/responsive-breakpoints';

const AppLayoutContainer = styled.main<{ noScroll?: boolean }>`
  display: flex;
  min-height: 100vh;
  margin: auto;
  flex-direction: column;
  justify-content: center;
  align-items: center;
  max-width: 1600px;
  padding: 0 1rem;
  ${breakpoints.md(`
    padding: 0 2rem;
  `)}
`;

export const AppLayout: Layout = ({ children }) => {
  return (
    <AppLayoutContainer>
      <Header />
      {children}
      <Footer />
    </AppLayoutContainer>
  );
};
