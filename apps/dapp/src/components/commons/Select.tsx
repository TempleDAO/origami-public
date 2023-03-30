import styled, { keyframes } from 'styled-components';
import ReactSelect from 'react-select';
import { textH2 } from '@/styles/mixins/text-styles';

const openingKeyframes = keyframes`
  0% {
    opacity: 0;
    transform: translateY(-1rem);
  }
  100% {
    opacity: 1;
    transform: translateY(0);
  }
`;

export const Select = styled(ReactSelect).attrs({
  classNamePrefix: 'react-select',
})`
  pointer-events: unset !important;

  .react-select__control {
    box-shadow: none;
    background-color: transparent;
    border: none;
    cursor: pointer;
    min-width: fit-content;
    flex-wrap: nowrap;
  }

  .react-select__control--is-disabled {
    opacity: 0.6;
    cursor: not-allowed;

    .react-select__dropdown-indicator:hover {
      color: ${({ theme }) => theme.colors.white};
    }
  }

  .react-select__dropdown-indicator {
    color: ${({ theme }) => theme.colors.white};

    &:hover {
      color: ${({ theme }) => theme.colors.greyLight};
    }
  }

  .react-select__indicator-separator {
    display: none;
  }

  .react-select__value-container {
    padding: 0;
  }

  .react-select__indicator {
    padding-right: 0;
  }

  .react-select__input-container {
    color: white;
  }

  //input placeholder/selected value
  .react-select__single-value {
    ${textH2}
    color: ${({ theme }) => theme.colors.greyLight};
  }

  .react-select__menu {
    overflow: hidden;
    background-color: ${({ theme }) => theme.colors.bgDark};
    margin: 0;
    top: 80%;
    animation: ${openingKeyframes} 0.2s ease-in-out;
  }

  .react-select__option {
    &:active {
      background-color: ${({ theme }) => theme.colors.greyLight};
    }
  }

  .react-select__option--is-focused {
    background-color: ${({ theme }) => theme.colors.greyLight};
    color: ${({ theme }) => theme.colors.white};
  }

  .react-select__option--is-selected {
    background-color: ${({ theme }) => theme.colors.greyMid};
  }
` as typeof ReactSelect;
