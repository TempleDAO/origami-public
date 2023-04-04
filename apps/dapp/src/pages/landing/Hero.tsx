import type { FC } from 'react';
import type { ApiCache } from '@/api/cache';

import styled from 'styled-components';
import Lottie from 'lottie-react';
import { Logo } from '@/components/Header/Logo';
import { LandingPageMetrics } from './LandingPageMetrics';
import { HeroCarousel } from './HeroCarousel';
import { StyledButton } from '@/components/commons/Button';
import breakpoints from '@/styles/responsive-breakpoints';

import heroAnimationMd from '@/lottie/hero-animation-md.json';

type HeroProps = {
  cache: ApiCache;
};

const carouselStrings = [
  'compound staking yields for any supported protocol',
  'maximize returns without sacrificing liquidity',
  'leverage your staked vault HOLDINGS',
  'now supporting gmx and glp',
];

export const Hero: FC<HeroProps> = ({ cache }) => {
  return (
    <HeroSection>
      <HeroLogo />
      <AnimationContainer>
        <Lottie id="lottie" animationData={heroAnimationMd} loop={true} />
      </AnimationContainer>
      <Content>
        <HeroText>/o.ri&apos;ga.mi/ the folding protocol for defi</HeroText>
        <HeroCarousel items={carouselStrings} />
        <ButtonLink as={'a'} href={'/deposit'}>
          Enter dapp
        </ButtonLink>
      </Content>
      <Container>
        <LandingPageMetrics cache={cache} />
      </Container>
    </HeroSection>
  );
};

const HERO_PADDING_PX = 32;

const HeroSection = styled.section`
  position: relative;
  background: rgba(36, 39, 44, 0.83);
  filter: brightness(100%);
`;

const AnimationContainer = styled.div`
  #lottie {
    display: none;
    position: absolute;
    z-index: -1;
    height: 30%;
    top: 0;
    left: 0;
    right: 0;

    ${breakpoints.lg(`
      display: block;
      height: 80%;
    `)}

    ${breakpoints.xl(`
      height: 100%;
    `)}
  }
`;

const HeroLogo = styled(Logo)`
  padding: ${HERO_PADDING_PX}px;
  padding-bottom: 0;
  height: 70px;

  ${breakpoints.sm(`
    height: 100px;
  `)}
`;

const Container = styled.div`
  box-sizing: border-box;
  top: 0;

  display: flex;
  flex-direction: column;

  width: 100%;
  height: 100%;

  padding: 20px 50px;

  ${breakpoints.sm(`
    padding: 40px 100px;
  `)}
`;

const Content = styled.article`
  display: flex;
  flex-direction: column;
  justify-content: center;
  align-items: center;
  padding: 100px ${HERO_PADDING_PX}px 0 ${HERO_PADDING_PX}px;

  ${breakpoints.sm(`
    padding-bottom: 50px;
    height: 100%;
  `)};
`;

const HeroText = styled.h1`
  margin: 1.25rem;
  text-align: center;
  text-transform: uppercase;
`;

const ButtonLink = styled(StyledButton)`
  margin-top: 40px;
  text-decoration: none;
  text-transform: uppercase;
  min-width: 150px;

  ${breakpoints.sm(`
    margin-top: 80px;
  `)};
`;
