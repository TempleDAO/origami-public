import { AppRoutes } from '@/app-routes';
import { Link } from '@/components/commons/Link';
import { PRIVACY_POLICY_URL, TERMS_OF_SERVICE_URL } from '@/urls';
import styled from 'styled-components';

export function Page() {
  return (
    <PageContainer>
      <H1>Origami Finance Disclaimers</H1>
      <p>
        The content on this website is for informational purposes only, and you
        should not construe any such information or other material as legal,
        tax, investment, financial, or other advice. Nothing contained on this
        webpage constitutes a solicitation, recommendation, endorsement, or
        offer to buy or sell any investment or financial instrument. Before
        making any investment decisions, please consult with a qualified
        professional. Any forward-looking expectations and opinions on this
        website are not fact and should not be relied upon. Past performance is
        not indicative of future results.
      </p>
      <p>
        <b>
          The opportunities discussed on this website are not available to
          persons who are located in, residents of, incorporated in, or have a
          registered agent in, the United States.
        </b>
        &nbsp; The information provided herein is not intended for distribution
        or use by any person or entity in any jurisdiction or country where such
        distribution or use would be contrary to applicable laws or regulations.
        It is your responsibility to ensure compliance with all applicable laws
        and regulations in your jurisdiction.
      </p>
      <p>
        <b>All users are required to comply with the Terms of Service at</b>
        <Link href={AppRoutes.TermsOfService}> {TERMS_OF_SERVICE_URL}</Link>
        &nbsp;
        <b>and Privacy Policy at </b>
        <Link href={AppRoutes.PrivacyPolicy}>{PRIVACY_POLICY_URL}</Link>
      </p>
      <p>
        The services available in or accessible through the website are provided
        “As is.” To the fullest extent permissible pursuant to applicable law,
        Origami Foundation (“Origami Finance”) disclaims all warranties,express
        or implied, including, but not limited to, implied warranties of
        merchantability, fitness for a particular purpose and non-infringement,
        and warranties implied from a course of performance or course of
        dealing. Origami Finance does not make any warranties about the
        completeness, reliability and accuracy of this information, warranty of
        merchantability or fitness for a particular purpose. This platform does
        not make any warranties about the completeness and accuracy of this
        information.
      </p>
      <p>
        Origami Finance and its suppliers make no warranty that the platform
        will:
      </p>
      <ul>
        <li>Meet your requirements;</li>
        <li>
          Be available on an uninterrupted, timely, secure, or error-free basis;
        </li>
        <li>Be reliable, complete or safe.</li>
      </ul>
      <p>
        The platform is not liable for any loss of any kind from any action
        taken or taken in reliance on material or information contained on the
        service. Origami Finance does not represent or warrant that the services
        and content on its platform are free of viruses or other harmful
        components.
      </p>
      <p>
        You bear full responsibility for verifying the identity and legitimacy
        of any information provided. Origami Finance makes no claims about any
        information provided. We cannot guarantee the security of any
        information disclosed online.
      </p>
      <p>
        Any action you take involving information you find on this website is
        strictly at your own risk. Origami Finance is not liable for any losses
        and/or damages you sustain in connection with the use of this website.
        Carefully consider the risk factors, purchase objectives, fees,
        expenses, and other information associated with any information listed
        on this website before making any purchase decision. All crypto assets
        are speculative in nature and involve a high degree of risk and
        uncertainty. There is no guarantee that any crypto asset will grow in
        value. Prior to making any purchase decision with regard to any
        information, you must undertake your own independent examination and
        investigation duct, including the merits and risks involved in any
        purchase, and must base your decision, including a determination of
        whether any product would be a suitable purchase for you, on such
        examination and investigation and you must not rely on Origami Finance
        in making such decision.
      </p>
      <p>
        Crypto assets are highly volatile, and can be affected by various
        factors, including market demand, regulatory developments, technological
        advancements, and macroeconomic conditions. Because crypto assets are a
        new technological innovation and have a limited history, they are highly
        speculative. The price of a crypto asset may be impacted by the
        transactions of a small number of holders of such crypto asset. Crypto
        assets may decline in popularity, acceptance or use, which may impact
        their price. Additionally, the regulatory landscape for crypto assets is
        evolving and varies across different jurisdictions. Governments and
        regulatory authorities may introduce new laws, regulations, or
        restrictions that could impact the legality, use, or value of crypto
        assets. Changes in regulatory policies may adversely affect the market
        for crypto assets and the ability to buy, sell, or hold them.
      </p>
      <p>
        Crypto assets may be susceptible to hacking, fraud, or technical
        glitches. Crypto asset transactions are irreversible, and if a user
        loses access to their digital wallet or private keys, their funds may be
        permanently lost. Users should take necessary precautions to secure
        their digital assets, such as using strong passwords, enabling
        two-factor authentication, security measures, and backup procedures. The
        underlying technology behind crypto assets is still relatively new and
        may be subject to technological vulnerabilities or limitations.
      </p>
      <p>
        Some crypto assets may have limited liquidity, meaning that there may
        not always be a readily available market to buy or sell these assets at
        desired prices. Illiquid markets can result in higher transaction costs,
        delays in executing trades, or difficulties in exiting positions. Crypto
        asset markets may be susceptible to market manipulation, such as
        pump-and-dump schemes, insider trading, or false rumors. Users should
        exercise caution and conduct thorough research before making any
        investment decisions.
      </p>
      <p>
        Crypto asset transactions may have tax implications. The tax treatment
        of crypto assets can vary by jurisdiction, and investors should consult
        with tax professionals to understand their tax obligations and reporting
        requirements.
      </p>
      <p>
        All products of any kind that may be listed on this website have not
        been approved or disapproved by the Securities and Exchange Commission,
        and are not registered under the Securities Act of 1933, the Investment
        Company Act of 1940, or any state securities commission or other
        regulatory body. Origami Finance is not registered as an Investment
        Adviser under the Investment Advisers Act of 1940, and is not registered
        as a Commodity Pool Operator or Commodity Trading Adviser under the
        Commodity Exchange Act.
      </p>
    </PageContainer>
  );
}

const PageContainer = styled.div`
  padding: 0 2rem;
  padding-bottom: 1.5rem;
`;

const H1 = styled.h1`
  line-height: 3rem;
`;
