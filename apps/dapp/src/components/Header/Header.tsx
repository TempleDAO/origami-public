import styled from 'styled-components';
import { Navigation } from '@/components/Navigation/Navigation';
import { Logo } from './Logo';
import { Link } from '../commons/Link';

export const Header = () => (
  <Container>
    <Row css="align-items: center;">
      <Link href={'/'}>
        <Logo />
      </Link>
      <Navigation />
    </Row>
  </Container>
);

const Container = styled.header`
  display: flex;
  align-items: center;
  box-sizing: border-box;
  padding: 1rem 0;
  width: 100%;
  margin-top: 1rem;
  a {
    line-height: 0;
  }
`;

const Row = styled.div`
  display: flex;
  justify-content: space-between;
  align-items: center;
  width: 100%;
  height: 100%;
`;
