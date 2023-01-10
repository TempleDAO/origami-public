import { createGlobalStyle } from 'styled-components';
import * as textStyles from './mixins/text-styles';

const ROOT_FONT_SIZE = 16;

export const GlobalStyle = createGlobalStyle`
  * {
    font-family: Exo;
    line-height: 150%;
  }

  body {
    background-color: ${({ theme }) => theme.colors.bgLight};
    color: ${({ theme }) => theme.colors.white};
    font-size: ${ROOT_FONT_SIZE}px;
    margin: 0;
  }

  h1 {
    ${textStyles.textH1}
  }

  h2 {
    ${textStyles.textH2}
  }

  h3 {
    ${textStyles.textH3}
  }

  h4 {
    ${textStyles.textH4}
  }

  h5 {
    ${textStyles.textH5}
  }

  // Scrollbars
  /* width */
  ::-webkit-scrollbar {
    width: 0.375rem  /* 6/16 */;
  }

  /* Track */
  ::-webkit-scrollbar-track {
    width: 1px;
    box-shadow: inset 0 0 0.3125rem  /* 5/16 */ ${({ theme }) =>
      theme.colors.greyMid};
    border-radius: 0.3125rem  /* 5/16 */;
  }

  /* Handle */
  ::-webkit-scrollbar-thumb {
    background-color:  ${({ theme }) => theme.colors.greyMid};
    box-shadow: 0 0 0.25rem  /* 4/16 */  ${({ theme }) => theme.colors.greyMid};
    border-radius: 0.1875rem  /* 3/16 */;
  }

  /* Handle on hover */
  ::-webkit-scrollbar-thumb:hover {
    background-color:  ${({ theme }) => theme.colors.greyMid};
  }
`;
