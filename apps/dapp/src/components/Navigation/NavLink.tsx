import type { FC } from 'react';

import styled, { css } from 'styled-components';
import { Link } from '@/components/commons/Link';
import {
  textPrimaryGradient,
  textUnderlinePrimaryGradient,
} from '@/styles/mixins/text-styles';

export type NavLinkProps = {
  label: string;
  href: string;
  routes?: string[];
  currentRoute?: string;
  className?: string;
};

export const NavLink: FC<NavLinkProps> = ({
  label,
  href,
  routes,
  currentRoute,
  className = '',
}) => {
  const isCurrent = !!routes && !!currentRoute && routes.includes(currentRoute);

  return (
    <Link href={href} removedecoration>
      <StyledLink className={className} $current={isCurrent}>
        {label}
      </StyledLink>
    </Link>
  );
};

const StyledLink = styled.span<{ $current: boolean }>`
  color: ${({ theme }) => theme.colors.greyLight};
  font-size: 1.125rem;
  font-weight: bold;
  ${textUnderlinePrimaryGradient};
  transition: 0.3s ease color;

  &:before {
    opacity: 0;
    transition: 0.3s opacity ease-in-out;
  }

  &:hover {
    color: ${({ theme }) => theme.colors.white};
  }

  ${({ $current }) =>
    $current &&
    css`
      ${textPrimaryGradient};
      &:before {
        opacity: 1;
      }
    `};
`;
