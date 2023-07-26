import { css } from 'styled-components';

//TODO: update naming convention

const clickableStyles = css`
  user-select: none;
  cursor: pointer;

  &:hover:not(:disabled) {
    //TODO: needs to be fixed for the new colors. this is just a tentative replacement
  }

  &:disabled {
    cursor: not-allowed;
  }
`;

export default clickableStyles;
