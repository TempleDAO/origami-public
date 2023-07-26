import type { FC } from 'react';

import styled from 'styled-components';
import { Icon } from '@/components/commons/Icon';
import breakpoints from '@/styles/responsive-breakpoints';
import { AppRoutes } from '@/app-routes';
import { Link } from '../commons/Link';

const SUBTEXT_FONT_SIZE = '0.9rem';

const socials = [
  { iconName: 'discord', href: 'https://discord.gg/origami' },
  { iconName: 'twitter', href: 'https://twitter.com/origami_fi' },
  // @todo update once properly published
  {
    iconName: 'gitbook',
    href: 'https://app.gitbook.com/o/j9MPDBLQNjXAd0d2eB0X/s/uQqfnSZUSHvj0FdEt8I8/introduction/what-is-origami',
  },
  //   { iconName: 'telegram', href: 'https://t.me/+fr8eQevq_6tjZDYx' },
  //   { iconName: 'medium', href: 'https://origamifinance.medium.com/' },
];

type FooterProps = {
  className?: string;
};

const Footer: FC<FooterProps> = ({ className }) => (
  <FooterContainer className={className}>
    <CopyrightContainer>
      <img src="/header-logo.svg" alt="Origami" height={40} />
      <TextContainer>
        <CopyrightText>© 2023 ORIGAMI. All rights reserved.</CopyrightText>
        <Link href={AppRoutes.Disclaimer} style={{ paddingRight: '1rem' }}>
          Disclaimer
        </Link>
        <Link href={AppRoutes.TermsOfService} style={{ paddingRight: '1rem' }}>
          Terms of Service
        </Link>
        <Link href={AppRoutes.PrivacyPolicy} style={{ paddingRight: '1rem' }}>
          Privacy Policy
        </Link>
      </TextContainer>
    </CopyrightContainer>
    <div>
      <CommunityTitle>COMMUNITY</CommunityTitle>
      <SocialsIconsContainer>
        {socials.map((props) => (
          <SocialsIconLink key={props.iconName} {...props} />
        ))}
      </SocialsIconsContainer>
    </div>
  </FooterContainer>
);

export default Footer;

const SocialsIconLink: FC<{ href: string; iconName: string }> = ({
  href,
  iconName,
}) => (
  <a href={href}>
    <IconStyled iconName={iconName} />
  </a>
);

const FooterContainer = styled.footer`
  display: flex;
  width: 100%;
  box-sizing: border-box;
  border-top: 1px solid ${({ theme }) => theme.colors.greyMid};
  padding: 1rem 2rem;
  margin-top: auto;
  justify-content: space-between;
  flex-direction: column;
  ${breakpoints.sm(`
    
    flex-direction: row;
  `)}
  ${breakpoints.md(`
    height: 8rem;
  `)}
`;

const CopyrightContainer = styled.div`
  display: flex;
  flex-direction: column;
  align-items: start;
  align-self: start;
  flex-shrink: 2;
  margin-right: 1.5rem;

  ${breakpoints.md(`
    align-self: start;
    margin-right: 0;
  `)}
`;

const TextContainer = styled.div`
  padding-top: 0.8rem;
`;

const CopyrightText = styled.small`
  display: block;
  color: ${({ theme }) => theme.colors.greyMid};
  font-size: ${SUBTEXT_FONT_SIZE};
`;

const IconStyled = styled(Icon)`
  transition: filter 300ms ease;
  &:hover {
    filter: contrast(1000%);
  }
`;

const SocialsIconsContainer = styled.div`
  display: flex;
  flex-shrink: 1;
  flex-wrap: wrap;
  justify-content: space-between;
  margin-top: 1rem;
  & > * {
    margin-right: 1rem;
    margin-bottom: 1rem;
  }

  ${breakpoints.sm(`
    flex-wrap: nowrap;
  `)}
`;

const CommunityTitle = styled.p`
  display: none;
  ${breakpoints.sm(`
    display: inline;
  `)}
`;
