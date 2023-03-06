import { HeroCarousel } from './HeroCarousel';

export default {
  title: 'Components/Content/HeroCarousel',
  component: HeroCarousel,
};

const CAROUSEL_STRINGS = [
  'SENTENCE 1',
  'SENTENCE 2',
  'SENTENCE 3',
  'SENTENCE 4',
  'SENTENCE 5',
  'SENTENCE 6',
];

export const Default = () => <HeroCarousel items={CAROUSEL_STRINGS} />;
