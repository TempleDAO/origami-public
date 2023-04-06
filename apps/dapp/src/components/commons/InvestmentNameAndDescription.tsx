import { FC } from 'react';
import { textH3, textP1 } from '@/styles/mixins/text-styles';
import styled from 'styled-components';
import { Icon } from './Icon';

export const LinkBox = styled.div`
  display: flex;
  flex-direction: row;
  column-gap: 0.5rem;
  align-items: center;
`;

const StyledAnchor = styled.a`
  margin-bottom: 4px;
  display: flex;
`;

const InvestmentName = styled.div`
  ${textH3}
  color: ${({ theme }) => theme.colors.white};
  transition: 300ms color ease;
`;

const Holder = styled.div`
  display: flex;
  flex-direction: column;
  &:hover {
    ${InvestmentName} {
      color: ${({ theme }) => theme.colors.greyLight};
    }
  }
`;

const InvestmentDescription = styled.div`
  ${textP1}
  color: ${({ theme }) => theme.colors.greyLight};
`;

type InvestmentNameAndDescriptionProps = {
  name: string;
  description: string;
  tokenExplorerUrl: string;
};

export const InvestmentNameAndDescription: FC<InvestmentNameAndDescriptionProps> =
  ({ name, description, tokenExplorerUrl }) => (
    <Holder>
      <LinkBox>
        <InvestmentName>{name}</InvestmentName>
        <StyledAnchor
          href={tokenExplorerUrl}
          target="_blank"
          rel="noopener noreferrer"
        >
          <Icon iconName={'open-in-new'} size={18} />
        </StyledAnchor>
      </LinkBox>
      <InvestmentDescription>{description}</InvestmentDescription>
    </Holder>
  );
