import type { FC } from 'react';

import { useMediaQuery } from '@/hooks/use-media-query';
import { theme } from '@/styles/theme';

type LogoProps = {
  className?: string;
};

export const Logo: FC<LogoProps> = ({ className }) => {
  const isDesktop = useMediaQuery(theme.responsiveBreakpoints.md);

  return (
    <img
      className={className}
      src="/header-logo.svg"
      alt="Origami"
      height={isDesktop ? 60 : 50}
    />
  );
};
