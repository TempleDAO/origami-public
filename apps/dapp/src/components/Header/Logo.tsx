import { useMediaQuery } from '@/hooks/use-media-query';
import { theme } from '@/styles/theme';

export const Logo = () => {
  const isDesktop = useMediaQuery(theme.responsiveBreakpoints.md);

  return (
    <img src="/header-logo.svg" alt="Origami" height={isDesktop ? 60 : 50} />
  );
};
