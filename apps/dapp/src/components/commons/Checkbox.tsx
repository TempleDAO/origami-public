import type { FC, MouseEventHandler } from 'react';

import styled from 'styled-components';
import { Icon } from '@/components/commons/Icon';

type CheckboxProps = {
  checked: boolean;
  disabled?: boolean;
  onClick?: MouseEventHandler;
};

export const Checkbox: FC<CheckboxProps> = ({ checked, disabled, onClick }) => {
  return checked ? (
    <Box>
      <StyledIcon size={16} iconName="checkbox" onClick={onClick} />
    </Box>
  ) : (
    <Box disabled={disabled} onClick={onClick} />
  );
};

const StyledIcon = styled(Icon)`
  cursor: pointer;
`;

const Box = styled.div<{ disabled?: boolean }>`
  display: flex;
  align-items: center;
  justify-content: center;

  width: 1.625rem;
  height: 1.625rem;
  box-sizing: border-box;
  border-radius: 100%;
  border: 2px solid ${({ theme }) => theme.colors.greyMid};
  cursor: pointer;
  ${({ disabled }) => disabled && `opacity: 0.5; cursor: not-allowed;`}

  &:hover {
    ${StyledIcon} {
      opacity: 0.6;
    }
  }
`;

export const CheckboxContainer = styled.div`
  display: flex;
  align-items: center;
  user-select: none;

  & > * {
    cursor: pointer;
  }
`;

export const CheckboxLabel = styled.label`
  font-size: 1rem;
  color: ${({ theme }) => theme.colors.white};
  margin-left: 1.5rem;
`;
