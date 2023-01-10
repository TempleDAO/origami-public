import type { FC } from 'react';
import type { TippyProps } from '@tippyjs/react';

import Tippy from '@tippyjs/react';
import styled from 'styled-components';
import { customColorRimShineSecondaryDim } from '@/styles/mixins/buttons/rim-shine/secondary-dim';
import 'tippy.js/dist/tippy.css';

type TooltipProps = TippyProps & { $bgColor?: string };

export const Tooltip: FC<TooltipProps> = ({ content, children, $bgColor }) => (
  <StyledTippy $bgColor={$bgColor} content={content}>
    {children}
  </StyledTippy>
);

const StyledTippy = styled(Tippy)<TooltipProps>`
  ${({ theme, $bgColor }) =>
    customColorRimShineSecondaryDim($bgColor ?? theme.colors.bgLight)}

  background-color: ${({ theme, $bgColor }) =>
    $bgColor ?? theme.colors.bgLight};

  div.tippy-content {
    background-color: ${({ theme, $bgColor }) =>
      $bgColor ?? theme.colors.bgLight};
  }

  div.tippy-arrow {
    color: ${({ theme, $bgColor }) => $bgColor ?? theme.colors.bgLight};
  }
`;
