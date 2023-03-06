import type { FC } from 'react';

import styled from 'styled-components';
import { Carousel as ResponsiveCarousel } from 'react-responsive-carousel';

import 'react-responsive-carousel/lib/styles/carousel.min.css';

export const HeroCarousel: FC<{ items: string[] }> = ({ items }) => {
  // if `infiniteLoop` is set to true, on the last item the carousel will slide back to the first item
  // instead we just duplicate the items so that the user does not see that animation
  const heroText = [...items, ...items, ...items, ...items, ...items];

  return (
    <div>
      <ResponsiveCarousel
        autoPlay
        showArrows={false}
        showStatus={false}
        showIndicators={false}
        showThumbs={false}
        interval={4000}
        width={'90vw'}
      >
        {heroText.map((item, index) => (
          <HeroText key={index}>{item}</HeroText>
        ))}
      </ResponsiveCarousel>
    </div>
  );
};

const HeroText = styled.h1`
  margin: 1.25rem;
  text-align: center;
  text-transform: uppercase;
`;
