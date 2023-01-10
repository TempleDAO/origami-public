import { FC } from 'react';
import styled from 'styled-components';
import breakpoints from '@/styles/responsive-breakpoints';

export interface LinksListProps {
  title: string;
  items: {
    label: string;
    link: string;
  }[];
}

const LINK_FONT_SIZE = '0.6rem';

const LinksList: FC<LinksListProps> = ({ title, items }) => {
  return (
    <ListContainer>
      <Title>{title.toUpperCase()}</Title>
      <ItemsList>
        {items.map((item) => (
          <li key={item.label}>
            <BulletPoint />
            <a href={item.link}>{item.label.toUpperCase()}</a>
          </li>
        ))}
      </ItemsList>
    </ListContainer>
  );
};

const ListContainer = styled.div`
  display: flex;
  flex-direction: column;
`;

const Title = styled.h5`
  font-size: 0.8rem;
  font-weight: bold;
  margin-top: 0;
  margin-bottom: 0.6rem;

  ${breakpoints.md(`margin-top: 0.8rem;`)}
`;

const ItemsList = styled.ul`
  margin: 0;
  list-style-type: none;
  padding-left: 0;

  li {
    display: flex;
    align-items: center;
    height: 1rem;
  }

  li > a {
    padding-top: 0.1rem;
    text-decoration: inherit;
    color: ${({ theme }) => theme.colors.greyMid};
    font-size: ${LINK_FONT_SIZE};
    line-height: ${LINK_FONT_SIZE};
  }
`;

const BulletPoint = styled.div`
  display: inline-block;
  width: ${LINK_FONT_SIZE};
  height: ${LINK_FONT_SIZE};
  margin-right: 0.2rem;
  background-color: ${({ theme }) => theme.colors.greyMid};
  box-shadow: 1px 1px 1px #535353;
`;

export default LinksList;
