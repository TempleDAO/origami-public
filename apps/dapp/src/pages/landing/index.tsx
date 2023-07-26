import type { FC } from 'react';
import { ApiCache } from '@/api/cache';

import styled from 'styled-components';
import { Hero } from './Hero';
import { Footer } from '@/components/Footer';
import { StyledButton } from '@/components/commons/Button';
import { useApiManager } from '@/hooks/use-api-manager';
import { textP1 } from '@/styles/mixins/text-styles';
import breakpoints from '@/styles/responsive-breakpoints';

export function Page() {
  const am = useApiManager();
  return <PageContent cache={am.cache} />;
}

interface PageContentProps {
  cache: ApiCache;
}

export const PageContent: FC<PageContentProps> = ({ cache }) => {
  return (
    <LandingPage>
      <Hero cache={cache} />
      <main>
        <MainTitle>HOW IT WORKS</MainTitle>
        <Features>
          <Feature
            imgSrc="/auto-compounding.svg"
            title="Auto Compound"
            text="ETH fees are harvested and refolded to grow your GMX and GLP stack faster"
          />
          <Feature
            imgSrc="/yield-optimization.svg"
            title="Yield Optimization"
            text="Vesting and multiplier points are managed automatically to optimize returns and liquidity"
          />
          <Feature
            imgSrc="/no-locking.svg"
            title="No Locking"
            text="Fully liquid staking means you can withdraw GMX or GLP from our vault at anytime without&nbsp;vesting"
          />
        </Features>
        <EnterDapp>
          <ButtonLink as={'a'} href={'/deposit'}>
            Enter dapp
          </ButtonLink>
        </EnterDapp>
      </main>
      <StyledFooter />
    </LandingPage>
  );
};

const LandingPage = styled.div`
  background-color: ${({ theme }) => theme.colors.bgDark};
`;

const MainTitle = styled.h1`
  text-align: center;
  margin-top: 42px;
  margin-bottom: 0;
  padding-bottom: 70px;
`;

type FeatureProps = {
  imgSrc: string;
  title: string;
  text: string;
};

const Feature: FC<FeatureProps> = ({ imgSrc, title, text }) => (
  <FeatureContainer>
    <img src={imgSrc} alt="" />
    <h2>{title}</h2>
    <p>{text}</p>
  </FeatureContainer>
);

const Features = styled.div`
  display: flex;
  justify-content: center;
  align-items: center;
  flex-direction: column;
  flex-wrap: wrap;
  gap: 40px;

  ${breakpoints.sm(`
    flex-direction: row;
    align-items: start;
    justify-content: space-evenly;
  `)}
`;

const FeatureContainer = styled.article`
  display: flex;
  flex-direction: column;
  justify-content: center;
  align-items: center;
  width: 240px;

  h2 {
    margin: 0;
    margin-top: 20px;
    margin-bottom: 10px;
    text-transform: uppercase;
  }

  p {
    margin: 0;
    ${textP1}
    text-align: center;
  }

  img {
    height: 150px;
  }
`;

const StyledFooter = styled(Footer)`
  margin: 80px auto;
  margin-bottom: 0;
  padding: 1rem 0;
  width: 90vw;

  color: ${({ theme }) => theme.colors.greyLight};
`;

const ButtonLink = styled(StyledButton)`
  margin-top: 80px;
  text-decoration: none;
  text-transform: uppercase;
  min-width: 150px;
`;

const EnterDapp = styled.div`
  display: flex;
  align-items: center;
  justify-content: center;
`;
