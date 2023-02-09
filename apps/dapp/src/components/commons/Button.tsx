import { FC, MouseEventHandler, useState } from 'react';
import styled, { css } from 'styled-components';

import { Spinner } from './Spinner';

import breakpoints from '@/styles/responsive-breakpoints';
import clickableStyles from '@/styles/mixins/clickable-styles';
import buttonShadowStyles from '@/styles/mixins/cards/shadow';
import buttonShadowDepressStyles from '@/styles/mixins/cards/shadow-small';

type RawButtonProps = {
  label: string;
  wide?: boolean;
  secondary?: boolean;
};

type ButtonProps = RawButtonProps & {
  onClick?: MouseEventHandler;
  disabled?: boolean;
  showSpinner?: boolean;
};

type AsyncButtonProps = RawButtonProps & {
  onClick?: () => Promise<void>;
};

export const Button: FC<ButtonProps> = ({
  showSpinner,
  label,
  onClick,
  disabled,
  secondary,
  wide,
  ...props
}) => (
  <StyledButton
    onClick={onClick}
    {...props}
    disabled={disabled || showSpinner}
    wide={wide}
    secondary={secondary}
  >
    {showSpinner ? <Spinner size={'small'} /> : label.toUpperCase()}
  </StyledButton>
);

// Shows a spinner whilst the onClick handler is running, disabled if an
// onClick handler is not provided
export const AsyncButton: FC<AsyncButtonProps> = ({ onClick, ...props }) => {
  const [showSpinner, setShowSpinner] = useState(false);
  async function onAsyncClick() {
    if (onClick) {
      try {
        setShowSpinner(true);
        await onClick();
      } catch (e) {
        console.error(e);
      } finally {
        setShowSpinner(false);
      }
    }
  }
  return (
    <Button
      onClick={onAsyncClick}
      disabled={!onClick}
      showSpinner={showSpinner}
      {...props}
    />
  );
};

const StyledButton = styled.button<{ wide?: boolean; secondary?: boolean }>`
  display: flex;
  align-items: center;
  justify-content: center;
  max-width: ${({ wide }) => !wide && '9.375rem'};
  max-height: 2.5rem;
  min-width: 6.25rem;
  flex-basis: ${({ wide }) => (wide ? 9.375 : 6.25)}rem;
  flex-shrink: 1;
  box-sizing: border-box;
  font-size: 0.875rem;
  font-weight: 700;
  border: 0;
  border-radius: 0.5rem;
  padding: 0.5rem 1rem;
  transition: 150ms ease;

  ${({ secondary }) =>
    secondary
      ? css`
          background: ${({ theme }) => theme.colors.bgMid};
          border: ${({ theme }) => `0.125rem solid ${theme.colors.greyMid}`};
          color: ${({ theme }) => theme.colors.white};
          &:disabled {
            border: ${({ theme }) => `0.125rem solid ${theme.colors.greyDark}`};
            color: ${({ theme }) => theme.colors.greyDark};
          }
          &:hover:not(:disabled) {
            border: ${({ theme }) => `0.125rem solid ${theme.colors.greyDark}`};
            color: ${({ theme }) => theme.colors.greyLight};
          }
          &:active:not(:disabled) {
            color: ${({ theme }) => theme.colors.greyDark};
          }
        `
      : css`
          background: ${({ theme }) => theme.colors.gradients.primary};
          color: ${({ theme }) => theme.colors.bgDark};
          ${buttonShadowStyles}
          &:hover, &:disabled {
            filter: brightness(60%);
          }
          &:disabled {
            box-shadow: none;
          }
          &:active:not(:disabled) {
            ${buttonShadowDepressStyles}
          }
        `}

  ${clickableStyles}

  ${breakpoints.md(`
    font-size: 1rem;
  `)}

  ${breakpoints.max(
    450,
    `
    min-width: unset;
    flex-basis: 9.375rem;
    `
  )}
`;
