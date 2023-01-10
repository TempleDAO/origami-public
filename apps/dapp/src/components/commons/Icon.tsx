import { FC, MouseEventHandler } from 'react';

import styled, { css } from 'styled-components';
import { noop } from '@/utils/noop';

const DEFAULT_SIZE = 24;

type IconProps = {
  size?: number;
  iconName: string;
  className?: string;
  onClick?: MouseEventHandler;
  hasBackground?: boolean;
};

export const Icon: FC<IconProps> = ({
  size = DEFAULT_SIZE,
  iconName,
  className,
  onClick,
  hasBackground = false,
}) => {
  if (hasBackground) {
    return (
      <IconBackground size={size}>
        <StyledImage
          src={`/icons/${iconName}.svg`}
          alt={iconName}
          size={size}
          className={className}
          onClick={onClick ?? noop}
        />
      </IconBackground>
    );
  }

  return (
    <StyledImage
      src={`/icons/${iconName}.svg`}
      alt={iconName}
      size={size}
      className={className}
      onClick={onClick ?? noop}
    />
  );
};

const StyledImage = styled.img<{ size: number }>`
  display: inline-block;
  width: ${({ size }) => size}px;
  height: ${({ size }) => size}px;
`;

const IconBackground = styled.div<{ size: number }>`
  ${({ size }) =>
    css`
      display: flex;
      justify-content: center;
      background: ${({ theme }) => theme.colors.bgDark};
      min-width: ${(size * 2) / 16}rem;
      min-height: ${(size * 2) / 16}rem;
      border-radius: 50%;
      display: flex;
      align-items: center;
      justify-content: center;
    `}
`;
