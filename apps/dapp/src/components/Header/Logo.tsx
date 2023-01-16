import { Image } from '@/components/commons/Image';
import { useMediaQuery } from '@/hooks/use-media-query';
import { theme } from '@/styles/theme';

export const Logo = () => {
  const isDesktop = useMediaQuery(theme.responsiveBreakpoints.md);

  return (
    <Image
      src="/header-logo.svg"
      alt="A logo for Origami"
      height={isDesktop ? 60 : 50}
      width={isDesktop ? 280 : 234}
    />
  );
};
