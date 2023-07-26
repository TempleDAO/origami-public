import { css } from 'styled-components';

//TODO: update naming convention
//TODO: will probably get deprecated

const boxStyles = css`
  color: ${({ theme }) => theme.colors.white};
  background-color: ${({ theme }) => theme.colors.greyMid};
  border-radius: 10px;
  border: 1px solid ${({ theme }) => theme.colors.greyLight};
`;

export default boxStyles;
