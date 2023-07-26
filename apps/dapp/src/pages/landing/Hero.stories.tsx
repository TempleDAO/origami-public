import { Hero } from './Hero';
import { useTestApis } from '@/api/test';

export default {
  title: 'Components/Content/Hero',
  component: Hero,
};

export const Default = () => {
  const { cache } = useTestApis();

  return <Hero cache={cache} />;
};
